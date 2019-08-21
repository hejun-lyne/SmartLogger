//
//  SLFunctionsWatcher.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/19.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLFunctionsWatcher.h"
#import "hashmap.h"
#import "blocks.h"
#import "fishhook.h"

#include <stdarg.h>
#include <stdio.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <pthread.h>

#include <objc/runtime.h>
#include <objc/message.h>

#import <CoreGraphics/CGAffineTransform.h>
#import <UIKit/UIGeometry.h>

#ifdef __arm64__
#define arg_list pa_list
#define int_up_cast(t) t
#define uint_up_cast(t) t
#include "ARM64Types.h"
#else
#define arg_list va_list
#define int_up_cast(t) int
#define uint_up_cast(t) unsigned int
#define pa_arg(args, type) va_arg(args, type)
#define pa_float(args) float_from_va_list(args)
#define pa_double(args) va_arg(args, double)

#define pa_two_ints(args, varType, varName, intType) \
varType varName = va_arg(args, varType); \

#define pa_two_doubles(args, t, varName) \
t varName = va_arg(args, t); \

#define pa_four_doubles(args, t, varName) \
t varName = va_arg(args, t); \

#endif

// The original objc_msgSend.
static id (*orig_objc_msgSend)(id, SEL, ...) = NULL;

// HashMap functions.
static int pointerEquality(void *a, void *b) {
    uintptr_t ia = reinterpret_cast<uintptr_t>(a);
    uintptr_t ib = reinterpret_cast<uintptr_t>(b);
    return ia == ib;
}

#ifdef __arm64__
// 64 bit hash from https://gist.github.com/badboy/6267743.
static inline NSUInteger pointerHash(void *v) {
    uintptr_t key = reinterpret_cast<uintptr_t>(v);
    key = (~key) + (key << 21); // key = (key << 21) - key - 1;
    key = key ^ (key >> 24);
    key = (key + (key << 3)) + (key << 8); // key * 265
    key = key ^ (key >> 14);
    key = (key + (key << 2)) + (key << 4); // key * 21
    key = key ^ (key >> 28);
    key = key + (key << 31);
    return key;
}
#else
// Robert Jenkin's 32 bit int hash.
static inline NSUInteger pointerHash(void *v) {
    uintptr_t a = reinterpret_cast<uintptr_t>(v);
    a = (a + 0x7ed55d16) + (a << 12);
    a = (a ^ 0xc761c23c) ^ (a >> 19);
    a = (a + 0x165667b1) + (a << 5);
    a = (a + 0xd3a2646c) ^ (a << 9);
    a = (a + 0xfd7046c5) + (a << 3);
    a = (a ^ 0xb55a4f09) ^ (a >> 16);
    return (NSUInteger)a;
}
#endif

// These classes support handling of void *s using callback functions, yet their methods
// accept (fake) ids. =/ i.e. objectForKey: and setObject:forKey: are dangerous for us because what
// looks like an id can be a regular old int and crash our program...
static Class NSMapTable_Class;
static Class NSHashTable_Class;
static inline BOOL isKindOfClass(Class selfClass, Class clazz) {
    for (Class candidate = selfClass; candidate; candidate = class_getSuperclass(candidate)) {
        if (candidate == clazz) {
            return YES;
        }
    }
    return NO;
}
static inline BOOL classSupportsArbitraryPointerTypes(Class clazz) {
    return isKindOfClass(clazz, NSMapTable_Class) || isKindOfClass(clazz, NSHashTable_Class);
}

#ifndef __arm64__
static float float_from_va_list(va_list args) {
    union {
        uint32_t i;
        float f;
    } value = {va_arg(args, uint32_t)};
    return value.f;
}
#endif

static inline void logNSStringForStruct(NSString *str) {
    printf("%s", [str UTF8String]);
}

static HashMapRef classMap;
static HashMapRef selsSet;

static inline BOOL selectorSetContainsSelector(HashMapRef selectorSet, SEL _cmd) {
    if (selectorSet == NULL) {
        return NO;
    }
    return HMGet(selectorSet, NULL) != NULL ||
    HMGet(selectorSet, _cmd) != NULL;
}

// Shared structures.
typedef struct CallRecord_ {
    id obj;
    SEL cmd;
    uintptr_t lr;
    int prevHitIndex; // Only used if isWatchHit is set.
    char isWatchHit;
} CallRecord;

typedef struct ThreadCallStack_ {
    char *spacesStr;
    CallRecord *stack;
    int allocatedLength;
    int index;
    int numWatchHits;
    int lastPrintedIndex;
    int lastHitIndex;
    char isLoggingEnabled;
    char isCompleteLoggingEnabled;
} ThreadCallStack;

// Store ThreadCallStack
static pthread_key_t threadKey;
#define DEFAULT_CALLSTACK_DEPTH 128
#define CALLSTACK_DEPTH_INCREMENT 64

static inline ThreadCallStack * getThreadCallStack() {
    ThreadCallStack *cs = (ThreadCallStack *)pthread_getspecific(threadKey);
    if (cs == NULL) {
        cs = (ThreadCallStack *)malloc(sizeof(ThreadCallStack));
        cs->spacesStr = (char *)malloc(DEFAULT_CALLSTACK_DEPTH + 1);
        memset(cs->spacesStr, ' ', DEFAULT_CALLSTACK_DEPTH);
        cs->spacesStr[DEFAULT_CALLSTACK_DEPTH] = '\0';
        cs->stack = (CallRecord *)calloc(DEFAULT_CALLSTACK_DEPTH, sizeof(CallRecord));
        cs->allocatedLength = DEFAULT_CALLSTACK_DEPTH;
        cs->index = cs->lastPrintedIndex = cs->lastHitIndex = -1;
        cs->numWatchHits = 0;
        cs->isLoggingEnabled = 1;
        cs->isCompleteLoggingEnabled = 0;
        pthread_setspecific(threadKey, cs);
    }
    return cs;
}

static inline void pushCallRecord(id obj, uintptr_t lr, SEL cmd, ThreadCallStack *cs) {
    int nextIndex = (++cs->index);
    if (nextIndex >= cs->allocatedLength) {
        cs->allocatedLength += CALLSTACK_DEPTH_INCREMENT;
        cs->stack = (CallRecord *)realloc(cs->stack, cs->allocatedLength * sizeof(CallRecord));
        cs->spacesStr = (char *)realloc(cs->spacesStr, cs->allocatedLength + 1);
        memset(cs->spacesStr, ' ', cs->allocatedLength);
        cs->spacesStr[cs->allocatedLength] = '\0';
    }
    CallRecord *newRecord = &cs->stack[nextIndex];
    newRecord->obj = obj;
    newRecord->cmd = cmd;
    newRecord->lr = lr;
    newRecord->isWatchHit = 0;
}

static inline CallRecord * popCallRecord(ThreadCallStack *cs) {
    return &cs->stack[cs->index--];
}

// Semi Public API - used to temporarily disable logging.

extern "C" void Watcher_enableLogging() {
    ThreadCallStack *cs = getThreadCallStack();
    cs->isLoggingEnabled = 1;
}

extern "C" void Watcher_disableLogging() {
    ThreadCallStack *cs = getThreadCallStack();
    cs->isLoggingEnabled = 0;
}

extern "C" int Watcher_isLoggingEnabled() {
    ThreadCallStack *cs = getThreadCallStack();
    return (int)cs->isLoggingEnabled;
}

@interface SLFunctionsWatcher()

- (void)onWatchHit:(ThreadCallStack *)cs args:(arg_list)args;
- (void)onNestCall:(ThreadCallStack *)cs args:(arg_list)args;

@end

static pthread_rwlock_t lock = PTHREAD_RWLOCK_INITIALIZER;
#define RLOCK pthread_rwlock_rdlock(&lock)
#define WLOCK pthread_rwlock_wrlock(&lock)
#define UNLOCK pthread_rwlock_unlock(&lock)
#define WATCH_ALL_SELECTORS_SELECTOR NULL

static inline void preObjc_msgSend_common(id mSelf, uintptr_t lr, SEL cmd, ThreadCallStack *cs, arg_list args) {
    if (mSelf == nil) {
        return;
    }
    Class clazz = object_getClass(mSelf);
    RLOCK;
    // Critical section - check for hits.
    BOOL isWatchedClass = selectorSetContainsSelector((HashMapRef)HMGet(classMap, (__bridge void *)clazz), cmd);
    BOOL isWatchedSel = (HMGet(selsSet, (void *)cmd) != NULL);
    UNLOCK;
    if (isWatchedClass || isWatchedSel) {
        [SLFunctionsWatcher.shared onWatchHit:cs args:args];
    } else if (cs->numWatchHits > 0 || cs->isCompleteLoggingEnabled) {
        [SLFunctionsWatcher.shared onNestCall:cs args:args];
    }
}

// Called in our replacementObjc_msgSend after calling the original objc_msgSend.
// This returns the lr in r0/x0.
uintptr_t postObjc_msgSend() {
    ThreadCallStack *cs = (ThreadCallStack *)pthread_getspecific(threadKey);
    CallRecord *record = popCallRecord(cs);
    if (record->isWatchHit) {
        --cs->numWatchHits;
        cs->lastHitIndex = record->prevHitIndex;
    }
    if (cs->lastPrintedIndex > cs->index) {
        cs->lastPrintedIndex = cs->index;
    }
    return record->lr;
}

// 32-bit vs 64-bit stuff.
#ifdef __arm64__
struct PointerAndInt_ {
    uintptr_t ptr;
    int i;
};

// arm64 hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
// Returns orig_objc_msgSend in x0 and isLoggingEnabled in x1.
struct PointerAndInt_ preObjc_msgSend(id self, uintptr_t lr, SEL _cmd, struct RegState_ *rs) {
    ThreadCallStack *cs = getThreadCallStack();
    if (!cs->isLoggingEnabled) { // Not enabled, just return.
        return (struct PointerAndInt_) {reinterpret_cast<uintptr_t>(orig_objc_msgSend), 0};
    }
    pushCallRecord(self, lr, _cmd, cs);
    pa_list args = (pa_list){ rs, ((unsigned char *)rs) + 208, 2, 0 }; // 208 is the offset of rs from the top of the stack.
    
    preObjc_msgSend_common(self, lr, _cmd, cs, args);
    
    return (struct PointerAndInt_) {reinterpret_cast<uintptr_t>(orig_objc_msgSend), 1};
}

// Our replacement objc_msgSend (arm64).
__attribute__((__naked__))
static void replacementObjc_msgSend() {
    __asm__ volatile (
                      // push {q0-q7}
                      "stp q6, q7, [sp, #-32]!\n"
                      "stp q4, q5, [sp, #-32]!\n"
                      "stp q2, q3, [sp, #-32]!\n"
                      "stp q0, q1, [sp, #-32]!\n"
                      // push {x0-x8, lr}
                      "stp x8, lr, [sp, #-16]!\n"
                      "stp x6, x7, [sp, #-16]!\n"
                      "stp x4, x5, [sp, #-16]!\n"
                      "stp x2, x3, [sp, #-16]!\n"
                      "stp x0, x1, [sp, #-16]!\n"
                      // Swap args around for call.
                      "mov x2, x1\n"
                      "mov x1, lr\n"
                      "mov x3, sp\n"
                      // Call preObjc_msgSend which puts orig_objc_msgSend into x0 and isLoggingEnabled into x1.
                      "bl __Z15preObjc_msgSendP11objc_objectmP13objc_selectorP9RegState_\n"
                      "mov x9, x0\n"
                      "mov x10, x1\n"
                      "tst x10, x10\n" // Set condition code for later branch.
                      // pop {x0-x8, lr}
                      "ldp x0, x1, [sp], #16\n"
                      "ldp x2, x3, [sp], #16\n"
                      "ldp x4, x5, [sp], #16\n"
                      "ldp x6, x7, [sp], #16\n"
                      "ldp x8, lr, [sp], #16\n"
                      // pop {q0-q7}
                      "ldp q0, q1, [sp], #32\n"
                      "ldp q2, q3, [sp], #32\n"
                      "ldp q4, q5, [sp], #32\n"
                      "ldp q6, q7, [sp], #32\n"
                      // Make sure it's enabled.
                      "b.eq Lpassthrough\n"
                      // Call through to the original objc_msgSend.
                      "blr x9\n"
                      // push {x0-x9}
                      "stp x0, x1, [sp, #-16]!\n"
                      "stp x2, x3, [sp, #-16]!\n"
                      "stp x4, x5, [sp, #-16]!\n"
                      "stp x6, x7, [sp, #-16]!\n"
                      "stp x8, x9, [sp, #-16]!\n" // Not sure if needed - push for alignment.
                      // push {q0-q7}
                      "stp q0, q1, [sp, #-32]!\n"
                      "stp q2, q3, [sp, #-32]!\n"
                      "stp q4, q5, [sp, #-32]!\n"
                      "stp q6, q7, [sp, #-32]!\n"
                      // Call our postObjc_msgSend hook.
                      "bl __Z16postObjc_msgSendv\n"
                      "mov lr, x0\n"
                      // pop {q0-q7}
                      "ldp q6, q7, [sp], #32\n"
                      "ldp q4, q5, [sp], #32\n"
                      "ldp q2, q3, [sp], #32\n"
                      "ldp q0, q1, [sp], #32\n"
                      // pop {x0-x9}
                      "ldp x8, x9, [sp], #16\n"
                      "ldp x6, x7, [sp], #16\n"
                      "ldp x4, x5, [sp], #16\n"
                      "ldp x2, x3, [sp], #16\n"
                      "ldp x0, x1, [sp], #16\n"
                      "ret\n"
                      
                      // Pass through to original objc_msgSend.
                      "Lpassthrough:\n"
                      "br x9"
                      );
}
#else
// arm32 hooking magic.

// Called in our replacementObjc_msgSend before calling the original objc_msgSend.
// This pushes a CallRecord to our stack, most importantly saving the lr.
// Returns orig_objc_msgSend.
uintptr_t preObjc_msgSend(id self, uintptr_t lr, SEL _cmd, va_list args) {
    ThreadCallStack *cs = getThreadCallStack();
    if (!cs->isLoggingEnabled) { // Not enabled, just return.
        return reinterpret_cast<uintptr_t>(orig_objc_msgSend);
    }
    pushCallRecord(self, lr, _cmd, cs);
    
    preObjc_msgSend_common(self, lr, _cmd, cs, args);
    
    return reinterpret_cast<uintptr_t>(orig_objc_msgSend);
}

// Our replacement objc_msgSend for arm32.
__attribute__((__naked__))
static void replacementObjc_msgSend() {
    __asm__ volatile (
                      // Make sure it's enabled.
                      // -fsanitize=alignment
//                      "push {r0-r3, lr}\n"
//                      "blx _Watcher_isLoggingEnabled\n"
//                      "mov r12, r0\n"
//                      "pop {r0-r3, lr}\n"
//                      "ands r12, r12\n"
//                      "beq Lpassthrough\n"
                      // Call our preObjc_msgSend hook - returns orig_objc_msgSend.
                      // Swap the args around for our call to preObjc_msgSend.
                      "push {r0, r1, r2, r3}\n"
                      "mov r2, r1\n"
                      "mov r1, lr\n"
                      "add r3, sp, #8\n"
                      "blx __Z15preObjc_msgSendP11objc_objectmP13objc_selectorPv\n"
                      "mov r12, r0\n"
                      "pop {r0, r1, r2, r3}\n"
                      // Call through to the original objc_msgSend.
                      "blx r12\n"
                      // Call our postObjc_msgSend hook.
                      "push {r0-r3}\n"
                      "blx __Z16postObjc_msgSendv\n"
                      "mov lr, r0\n"
                      "pop {r0-r3}\n"
                      "bx lr\n"
                      // Pass through to original objc_msgSend.
                      "Lpassthrough:\n"
                      "movw  r12, :lower16:(__ZL17orig_objc_msgSend-(Loffset+4))\n"
                      "movt  r12, :upper16:(__ZL17orig_objc_msgSend-(Loffset+4))\n"
                      "Loffset:\n"
                      "add r12, pc\n"
                      "ldr r12, [r12]\n"
                      "bx r12\n"
                      );
}

#endif

__attribute__((constructor))
extern "C" void WatcherSetup() {
    
    NSMapTable_Class = [objc_getClass("NSMapTable") class];
    NSHashTable_Class = [objc_getClass("NSHashTable") class];
    classMap = HMCreate(&pointerEquality, &pointerHash);
    selsSet = HMCreate(&pointerEquality, &pointerHash);
    
    rebind_symbols((struct rebinding[1]){{"objc_msgSend", (void *)replacementObjc_msgSend, (void **)&orig_objc_msgSend}}, 1);
}

@implementation SLFunctionsWatcher

+ (instancetype)shared
{
    static SLFunctionsWatcher *s_funcsWatcher;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_funcsWatcher = [SLFunctionsWatcher new];
    });
    return s_funcsWatcher;
}

+ (void)watchClass:(Class)cls selector:(SEL)selector
{
    if (cls == nil || selector == nil) {
        return;
    }
    
    WLOCK;
    HashMapRef selectorSet = (HashMapRef)HMGet(classMap, (__bridge void *)cls);
    if (selectorSet == NULL) {
        selectorSet = HMCreate(&pointerEquality, &pointerHash);
        HMPut(classMap, (__bridge void *)cls, selectorSet);
    }
    
    HMPut(selectorSet, selector, (void *)YES);
    UNLOCK;
}

- (void)onWatchHit:(ThreadCallStack *)cs args:(arg_list)args
{
    const int hitIndex = cs->index;
    CallRecord *hitRecord = &cs->stack[hitIndex];
    hitRecord->isWatchHit = 1;
    hitRecord->prevHitIndex = cs->lastHitIndex;
    cs->lastHitIndex = hitIndex;
    ++cs->numWatchHits;
    
    // Log previous calls if necessary.
    for (int i = cs->lastPrintedIndex + 1; i < hitIndex; ++i) {
        CallRecord record = cs->stack[i];
        
        // Modify spacesStr.
        char *spaces = cs->spacesStr;
        spaces[i] = '\0';
        
        // Print class
        Class kind = object_getClass(record.obj);
        bool isMetaClass = class_isMetaClass(kind);
        if (isMetaClass) {
            printf("%s%s+|%s %s|\n", spaces, spaces, class_getName(kind), sel_getName(record.cmd));
        } else {
            printf("%s%s-|%s %s| @<%p>\n", spaces, spaces, class_getName(kind), sel_getName(record.cmd), (__bridge void *)record.obj);
        }
        
        // Clean up spacesStr.
        spaces[i] = ' ';
    }
    
    // Log the hit call.
    char *spaces = cs->spacesStr;
    spaces[hitIndex] = '\0';
    Class kind = object_getClass(hitRecord->obj);
    BOOL isMetaClass = class_isMetaClass(kind);
    [self logWithClass:kind isMetaClass:isMetaClass object:hitRecord->obj selector:hitRecord->cmd spaces:spaces args:args];
    
    // Clean up spacesStr.
    spaces[hitIndex] = ' ';
    
    // Lastly, set the lastPrintedIndex.
    cs->lastPrintedIndex = hitIndex;
}

- (void)onNestCall:(ThreadCallStack *)cs args:(arg_list)args
{
    const int curIndex = cs->index;
    if (cs->isCompleteLoggingEnabled || (curIndex - cs->lastHitIndex) <= CALLSTACK_DEPTH_INCREMENT) {
        
        // Log the current call.
        char *spaces = cs->spacesStr;
        spaces[curIndex] = '\0';
        CallRecord curRecord = cs->stack[curIndex];
        Class kind = object_getClass(curRecord.obj);
        BOOL isMetaClass = class_isMetaClass(kind);
        [self logWithClass:kind isMetaClass:isMetaClass object:curRecord.obj selector:curRecord.cmd spaces:spaces args:args];
        
        // Reset
        spaces[curIndex] = ' ';
        
        // Lastly, set the lastPrintedIndex.
        cs->lastPrintedIndex = curIndex;
    }
}

- (void)logWithClass:(Class)clazz isMetaClass:(BOOL)isMetaClass object:(id)object selector:(SEL)selector spaces:(char *)spaces args:(arg_list)args
{
    Method method = (isMetaClass) ? class_getClassMethod(clazz, _cmd) : class_getInstanceMethod(clazz, _cmd);
    if (method == nil) {
        return;
    }
    
    const char *normalFormatStr = "%s%s***-|%s@<%p> %s|";
    const char *metaClassFormatStr = "%s%s***+|%s %s|";
    if (isMetaClass) {
        printf(metaClassFormatStr, spaces, spaces, class_getName(clazz), sel_getName(selector));
    } else {
        printf(normalFormatStr, spaces, spaces, class_getName(clazz), (__bridge void *)object, sel_getName(selector));
    }
    
    const char *typeEncoding = method_getTypeEncoding(method);
    if (!typeEncoding || classSupportsArbitraryPointerTypes(clazz)) {
        printf(" ~NO ENCODING~***\n");
        return;
    }
    
    @try {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:typeEncoding];
        const NSUInteger numberOfArguments = [signature numberOfArguments];
        for (NSUInteger index = 2; index < numberOfArguments; ++index) {
            const char *type = [signature getArgumentTypeAtIndex:index];
            printf(" ");
            if (![self logArgument:type args:args]) { // Can't understand arg - probably a struct.
                printf("~BAIL on \"%s\"~", type);
                break;
            }
        }
    } @catch(NSException *e) {
        printf("~BAD ENCODING~");
    }
}

- (void)logObject:(id)object
{
    static Class NSString_Class = objc_getClass("NSString");
    static Class NSBlock_Class = objc_getClass("NSBlock");
    
    if (object == nil) {
        printf("nil");
        return;
    }
    Class kind = object_getClass(object);
    if (class_isMetaClass(kind)) {
        printf("[%s class]", class_getName(object));
        return;
    }
    if (isKindOfClass(kind, NSString_Class)) {
        printf("@\"%s\"", [object UTF8String]);
        return;
    }
    if (isKindOfClass(kind, NSBlock_Class)) {
        logBlock(nil, object);
        return;
    }
    printf("<%s@%p>", class_getName(kind), (__bridge void *)(object));
}

- (BOOL)logArgument:(const char *)type args:(arg_list)args
{
loop:
    switch(*type) {
        case '#': // A class object (Class).
        case '@': { // An object (whether statically typed or typed id).
            id value = pa_arg(args, id);
            [self logObject:value];
        } break;
        case ':': { // A method selector (SEL).
            SEL value = pa_arg(args, SEL);
            if (value == NULL) {
                printf("NULL");
            } else {
                printf("@selector(%s)", sel_getName(value));
            }
        } break;
        case '*': { // A character string (char *).
            const char *value = pa_arg(args, const char *);
            printf("\"%s\"", value);
        } break;
        case '^': { // A pointer to type (^type).
            void *value = pa_arg(args, void *);
            if (value == NULL) {
                printf("NULL");
            } else {
                printf("%p", value);
            }
        } break;
        case 'B': { // A C++ bool or a C99 _Bool.
            bool value = pa_arg(args, int_up_cast(bool));
            printf("%s", value ? "true" : "false");
        } break;
        case 'c': { // A char.
            signed char value = pa_arg(args, int_up_cast(char));
            printf("%d", value);
        } break;
        case 'C': { // An unsigned char.
            unsigned char value = pa_arg(args, uint_up_cast(unsigned char));
            printf("%d", value);
        } break;
        case 's': { // A short.
            short value = pa_arg(args, int_up_cast(short));
            printf("%d", value);
        } break;
        case 'S': { // An unsigned short.
            unsigned short value = pa_arg(args, uint_up_cast(unsigned short));
            printf("%u", value);
        } break;
        case 'i': { // An int.
            int value = pa_arg(args, int);
            if (value == INT_MAX) {
                printf("INT_MAX");
            } else {
                printf("%d", value);
            }
        } break;
        case 'I': { // An unsigned int.
            unsigned int value = pa_arg(args, unsigned int);
            printf("%u", value);
        } break;
#ifdef __arm64__
        case 'l': { // A long - treated as a 32-bit quantity on 64-bit programs.
            int value = pa_arg(args, int);
            printf("%d", value);
        } break;
        case 'L': { // An unsigned long - treated as a 32-bit quantity on 64-bit programs.
            unsigned int value = pa_arg(args, unsigned int);
            printf("%u", value);
        } break;
#else
        case 'l': { // A long.
            long value = pa_arg(args, long);
            printf("%ld", value);
        } break;
        case 'L': { // An unsigned long.
            unsigned long value = pa_arg(args, unsigned long);
            printf("%lu", value);
        } break;
#endif
        case 'q': { // A long long.
            long long value = pa_arg(args, long long);
            printf("%lld", value);
        } break;
        case 'Q': { // An unsigned long long.
            unsigned long long value = pa_arg(args, unsigned long long);
            printf("%llu", value);
        } break;
        case 'f': { // A float.
            float value = pa_float(args);
            printf("%g", value);
        } break;
        case 'd': { // A double.
            double value = pa_double(args);
            printf("%g", value);
        } break;
        case '{': { // A struct. We check for some common structs.
            if (strncmp(type, "{CGAffineTransform=", 19) == 0) {
#ifdef __arm64__
                CGAffineTransform *ptr = (CGAffineTransform *)pa_arg(args, void *);
                logNSStringForStruct(NSStringFromCGAffineTransform(*ptr));
#else
                CGAffineTransform at = va_arg(args, CGAffineTransform);
                logNSStringForStruct(NSStringFromCGAffineTransform(at));
#endif
            } else if (strncmp(type, "{CGPoint=", 9) == 0) {
                pa_two_doubles(args, CGPoint, point)
                logNSStringForStruct(NSStringFromCGPoint(point));
            } else if (strncmp(type, "{CGRect=", 8) == 0) {
                pa_four_doubles(args, UIEdgeInsets, insets)
                CGRect rect = CGRectMake(insets.top, insets.left, insets.bottom, insets.right);
                logNSStringForStruct(NSStringFromCGRect(rect));
            } else if (strncmp(type, "{CGSize=", 8) == 0) {
                pa_two_doubles(args, CGSize, size)
                logNSStringForStruct(NSStringFromCGSize(size));
            }  else if (strncmp(type, "{UIEdgeInsets=", 14) == 0) {
                pa_four_doubles(args, UIEdgeInsets, insets)
                logNSStringForStruct(NSStringFromUIEdgeInsets(insets));
            } else if (strncmp(type, "{UIOffset=", 10) == 0) {
                pa_two_doubles(args, UIOffset, offset)
                logNSStringForStruct(NSStringFromUIOffset(offset));
            } else if (strncmp(type, "{_NSRange=", 10) == 0) {
                pa_two_ints(args, NSRange, range, unsigned long);
                logNSStringForStruct(NSStringFromRange(range));
            } else { // Nope.
                return false;
            }
        } break;
        case 'N': // inout.
        case 'n': // in.
        case 'O': // bycopy.
        case 'o': // out.
        case 'R': // byref.
        case 'r': // const.
        case 'V': // oneway.
            ++type;
            goto loop;
        default:
            return false;
    }
    return true;
}

@end
