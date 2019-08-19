//
//  SLLogMessage.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogMessage.h"

#import <pthread.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <mach/mach_host.h>
#import <mach/host_info.h>
#import <libkern/OSAtomic.h>
#import <Availability.h>
#if TARGET_OS_IOS
#import <UIKit/UIDevice.h>
#endif

@implementation SLLogMessage

// Can we use DISPATCH_CURRENT_QUEUE_LABEL ?
// Can we use dispatch_get_current_queue (without it crashing) ?
//
// a) Compiling against newer SDK's (iOS 7+/OS X 10.9+) where DISPATCH_CURRENT_QUEUE_LABEL is defined
//    on a (iOS 7.0+/OS X 10.9+) runtime version
//
// b) Systems where dispatch_get_current_queue is not yet deprecated and won't crash (< iOS 6.0/OS X 10.9)
//
//    dispatch_get_current_queue(void);
//      __OSX_AVAILABLE_BUT_DEPRECATED(__MAC_10_6,__MAC_10_9,__IPHONE_4_0,__IPHONE_6_0)

#if TARGET_OS_IOS

// Compiling for iOS

static BOOL _use_dispatch_current_queue_label;
static BOOL _use_dispatch_get_current_queue;

static void _dispatch_queue_label_init_once(void * __attribute__((unused)) context)
{
    _use_dispatch_current_queue_label = (UIDevice.currentDevice.systemVersion.floatValue >= 7.0f);
    _use_dispatch_get_current_queue = (!_use_dispatch_current_queue_label && UIDevice.currentDevice.systemVersion.floatValue >= 6.1f);
}

static __inline__ __attribute__((__always_inline__)) void _dispatch_queue_label_init()
{
    static dispatch_once_t onceToken;
    dispatch_once_f(&onceToken, NULL, _dispatch_queue_label_init_once);
}

#define USE_DISPATCH_CURRENT_QUEUE_LABEL (_dispatch_queue_label_init(), _use_dispatch_current_queue_label)
#define USE_DISPATCH_GET_CURRENT_QUEUE   (_dispatch_queue_label_init(), _use_dispatch_get_current_queue)

#elif TARGET_OS_WATCH || TARGET_OS_TV

// Compiling for watchOS, tvOS

#define USE_DISPATCH_CURRENT_QUEUE_LABEL YES
#define USE_DISPATCH_GET_CURRENT_QUEUE   NO

#else

// Compiling for Mac OS X

#ifndef MAC_OS_X_VERSION_10_9
#define MAC_OS_X_VERSION_10_9            1090
#endif

#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_9 // Mac OS X 10.9 or later required

#define USE_DISPATCH_CURRENT_QUEUE_LABEL YES
#define USE_DISPATCH_GET_CURRENT_QUEUE   NO

#else

static BOOL _use_dispatch_current_queue_label;
static BOOL _use_dispatch_get_current_queue;

static void _dispatch_queue_label_init_once(void * __attribute__((unused)) context)
{
    _use_dispatch_current_queue_label = [NSTimer instancesRespondToSelector : @selector(tolerance)]; // OS X 10.9+
    _use_dispatch_get_current_queue = !_use_dispatch_current_queue_label;                            // < OS X 10.9
}

static __inline__ __attribute__((__always_inline__)) void _dispatch_queue_label_init()
{
    static dispatch_once_t onceToken;
    dispatch_once_f(&onceToken, NULL, _dispatch_queue_label_init_once);
}

#define USE_DISPATCH_CURRENT_QUEUE_LABEL (_dispatch_queue_label_init(), _use_dispatch_current_queue_label)
#define USE_DISPATCH_GET_CURRENT_QUEUE   (_dispatch_queue_label_init(), _use_dispatch_get_current_queue)

#endif

#endif /* if TARGET_OS_IOS */

// Should we use pthread_threadid_np ?
// With iOS 8+/OSX 10.10+ NSLog uses pthread_threadid_np instead of pthread_mach_thread_np

#if TARGET_OS_IOS

// Compiling for iOS

#ifndef kCFCoreFoundationVersionNumber_iOS_8_0
#define kCFCoreFoundationVersionNumber_iOS_8_0 1140.10
#endif

#define USE_PTHREAD_THREADID_NP                (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0)

#elif TARGET_OS_WATCH || TARGET_OS_TV

// Compiling for watchOS, tvOS

#define USE_PTHREAD_THREADID_NP                YES

#else

// Compiling for Mac OS X

#ifndef kCFCoreFoundationVersionNumber10_10
#define kCFCoreFoundationVersionNumber10_10    1151.16
#endif

#define USE_PTHREAD_THREADID_NP                (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber10_10)

#endif /* if TARGET_OS_IOS */

- (instancetype)init {
    self = [super init];
    return self;
}

- (instancetype)initWithMessage:(NSString *)message
                          level:(SLLogLevel)level
                           flag:(SLLogFlag)flag
                           file:(NSString *)file
                       function:(NSString *)function
                           line:(NSUInteger)line
                            tag:(NSString *)tag
                      timestamp:(NSDate *)timestamp {
    if ((self = [super init])) {
        _message      = message;
        _level        = level;
        _flag         = flag;
        _file         = file;
        _function     = function;
        _line         = line;
        _tag          = tag;
        _timestamp    = timestamp ?: [NSDate new];
        
        if (USE_PTHREAD_THREADID_NP) {
            __uint64_t tid;
            pthread_threadid_np(NULL, &tid);
            _threadID = [[NSString alloc] initWithFormat:@"%llu", tid];
        } else {
            _threadID = [[NSString alloc] initWithFormat:@"%x", pthread_mach_thread_np(pthread_self())];
        }
        _threadName   = NSThread.currentThread.name;
        
        // Get the file name without extension
        _fileName = [_file lastPathComponent];
        NSUInteger dotLocation = [_fileName rangeOfString:@"." options:NSBackwardsSearch].location;
        if (dotLocation != NSNotFound)
        {
            _fileName = [_fileName substringToIndex:dotLocation];
        }
        
        // Try to get the current queue's label
        if (USE_DISPATCH_CURRENT_QUEUE_LABEL) {
            _queueLabel = [[NSString alloc] initWithFormat:@"%s", dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)];
        } else if (USE_DISPATCH_GET_CURRENT_QUEUE) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            dispatch_queue_t currentQueue = dispatch_get_current_queue();
#pragma clang diagnostic pop
            _queueLabel = [[NSString alloc] initWithFormat:@"%s", dispatch_queue_get_label(currentQueue)];
        } else {
            _queueLabel = @""; // iOS 6.x only
        }
    }
    return self;
}

- (instancetype)initWithMessage:(NSString *)message tag:(NSString *)tag {
    if (self = [super init]) {
        _flag = SLLogFlagInfo;
        _level = SLLogLevelInfo;
        _message = message;
        _tag = tag;
        _noFormatter = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone * __attribute__((unused)))zone {
    SLLogMessage *newMessage = [SLLogMessage new];
    
    newMessage->_message = _message;
    newMessage->_level = _level;
    newMessage->_flag = _flag;
    newMessage->_file = _file;
    newMessage->_fileName = _fileName;
    newMessage->_function = _function;
    newMessage->_line = _line;
    newMessage->_tag = _tag;
    newMessage->_timestamp = _timestamp;
    newMessage->_threadID = _threadID;
    newMessage->_threadName = _threadName;
    newMessage->_queueLabel = _queueLabel;
    newMessage->_noFormatter = _noFormatter;
    
    return newMessage;
}

@end
