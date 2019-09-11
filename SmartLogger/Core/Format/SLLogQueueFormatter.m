//
//  SLLogQueueFormatter.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogQueueFormatter.h"
#import "SLLogMessage.h"

#import <Foundation/Foundation.h>
#import <pthread/pthread.h>
#import <objc/runtime.h>
#import <libkern/OSAtomic.h>
#import <stdatomic.h>

@interface SLLogQueueFormatter () {
    SLLogQueueFormatterMode _mode;
    NSString *_dateFormatterKey;
    
    int32_t _osAtomicLoggerCount;
    atomic_int_fast32_t _atomicLoggerCount;
    NSDateFormatter *_threadUnsafeDateFormatter; // Use [self stringFromDate]
    
    pthread_mutex_t _mutex;
    
    NSUInteger _minQueueLength;           // _prefix == Only access via atomic property
    NSUInteger _maxQueueLength;           // _prefix == Only access via atomic property
    NSMutableDictionary *_replacements;   // _prefix == Only access from within spinlock
}

@end

@implementation SLLogQueueFormatter

- (instancetype)init
{
    if ((self = [super init])) {
        // default for shared
        _mode = SLLogQueueFormatterModeShared;
        
        // avoid call subclass configureDateFormatter:
        Class cls = [self class];
        Class superClass = class_getSuperclass(cls);
        SEL configMethodName = @selector(configureDateFormatter:);
        Method configMethod = class_getInstanceMethod(cls, configMethodName);
        while (class_getInstanceMethod(superClass, configMethodName) == configMethod) {
            cls = superClass;
            superClass = class_getSuperclass(cls);
        }
        // now `cls` is the class that provides implementation for `configureDateFormatter:`
        _dateFormatterKey = [NSString stringWithFormat:@"%s_NSDateFormatter", class_getName(cls)];
        
        _osAtomicLoggerCount = 0;
        _threadUnsafeDateFormatter = nil;
        
        _minQueueLength = 0;
        _maxQueueLength = 0;
        pthread_mutex_init(&_mutex, NULL);
        _replacements = [[NSMutableDictionary alloc] init];
        
        _replacements[@"com.apple.main-thread"] = @"main";
    }
    
    return self;
}

- (instancetype)initWithMode:(SLLogQueueFormatterMode)mode
{
    if ((self = [self init])) {
        _mode = mode;
    }
    return self;
}

- (void)dealloc
{
    pthread_mutex_destroy(&_mutex);
}

#pragma mark Configuration

@synthesize minQueueLength = _minQueueLength;
@synthesize maxQueueLength = _maxQueueLength;

- (NSString *)replacementStringForQueueLabel:(NSString *)longLabel
{
    NSString *result = nil;
    
    pthread_mutex_lock(&_mutex);
    {
        result = _replacements[longLabel];
    }
    pthread_mutex_unlock(&_mutex);
    
    return result;
}

- (void)setReplacementString:(NSString *)shortLabel forQueueLabel:(NSString *)longLabel
{
    pthread_mutex_lock(&_mutex);
    {
        if (shortLabel) {
            _replacements[longLabel] = shortLabel;
        } else {
            [_replacements removeObjectForKey:longLabel];
        }
    }
    pthread_mutex_unlock(&_mutex);
}

#pragma mark - ATHLogFormatter

- (NSDateFormatter *)createDateFormatter
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [self configureDateFormatter:formatter];
    return formatter;
}

- (void)configureDateFormatter:(NSDateFormatter *)dateFormatter {
    [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss:SSS(Z)"];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Shanghai"]];
    
    NSString *calendarIdentifier = nil;
#if defined(__IPHONE_8_0) || defined(__MAC_10_10)
    calendarIdentifier = NSCalendarIdentifierGregorian;
#else
    calendarIdentifier = NSGregorianCalendar;
#endif
    
    [dateFormatter setCalendar:[[NSCalendar alloc] initWithCalendarIdentifier:calendarIdentifier]];
}

- (NSString *)stringFromDate:(NSDate *)date
{
    
    NSDateFormatter *dateFormatter = nil;
    if (_mode == SLLogQueueFormatterModeAlone) {
        // Single-threaded mode.
        
        dateFormatter = _threadUnsafeDateFormatter;
        if (dateFormatter == nil) {
            dateFormatter = [self createDateFormatter];
            _threadUnsafeDateFormatter = dateFormatter;
        }
    } else {
        // Multi-threaded mode.
        // NSDateFormatter is NOT thread-safe.
        NSString *key = _dateFormatterKey;
        NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
        dateFormatter = threadDictionary[key];
        if (dateFormatter == nil) {
            dateFormatter = [self createDateFormatter];
            threadDictionary[key] = dateFormatter;
        }
    }
    
    return [dateFormatter stringFromDate:date];
}

- (NSString *)queueThreadLabelForLogMessage:(SLLogMessage *)logMessage
{
    
    NSUInteger minQueueLength = self.minQueueLength;
    NSUInteger maxQueueLength = self.maxQueueLength;
    
    NSString *queueThreadLabel = nil;
    BOOL useQueueLabel = YES;
    BOOL useThreadName = NO;
    
    if (logMessage->_queueLabel) {
        // 如果是下面这些线程，我们更希望使用呢 threadName 或者 machThreadID.
        NSArray *names = @[
                           @"com.apple.root.low-priority",
                           @"com.apple.root.default-priority",
                           @"com.apple.root.high-priority",
                           @"com.apple.root.low-overcommit-priority",
                           @"com.apple.root.default-overcommit-priority",
                           @"com.apple.root.high-overcommit-priority",
                           @"com.apple.root.default-qos.overcommit"
                           ];
        
        for (NSString * name in names) {
            if ([logMessage->_queueLabel isEqualToString:name]) {
                useQueueLabel = NO;
                useThreadName = [logMessage->_threadName length] > 0;
                break;
            }
        }
    } else {
        useQueueLabel = NO;
        useThreadName = [logMessage->_threadName length] > 0;
    }
    
    if (useQueueLabel || useThreadName) {
        NSString *fullLabel;
        NSString *abrvLabel;
        
        if (useQueueLabel) {
            fullLabel = logMessage->_queueLabel;
        } else {
            fullLabel = logMessage->_threadName;
        }
        
        pthread_mutex_lock(&_mutex);
        {
            abrvLabel = _replacements[fullLabel];
        }
        pthread_mutex_unlock(&_mutex);
        
        if (abrvLabel) {
            queueThreadLabel = abrvLabel;
        } else {
            queueThreadLabel = fullLabel;
        }
    } else {
        queueThreadLabel = logMessage->_threadID;
    }
    
    NSUInteger labelLength = [queueThreadLabel length];
    
    if ((maxQueueLength > 0) && (labelLength > maxQueueLength)) {
        // Truncate
        return [queueThreadLabel substringToIndex:maxQueueLength];
    } else if (labelLength < minQueueLength) {
        // Padding
        NSUInteger numSpaces = minQueueLength - labelLength;
        char spaces[numSpaces + 1];
        memset(spaces, ' ', numSpaces);
        spaces[numSpaces] = '\0';
        return [NSString stringWithFormat:@"%@%s", queueThreadLabel, spaces];
    } else {
        // Exact
        return queueThreadLabel;
    }
}

- (NSString *)formatLogMessage:(SLLogMessage *)logMessage
{
    if (logMessage.noFormatter) {
        return [NSString stringWithFormat:@"[%@] %@", logMessage->_tag, logMessage->_message];
    }
    NSString *timestamp = [self stringFromDate:(logMessage->_timestamp)];
    NSString *queueThreadLabel = [self queueThreadLabelForLogMessage:logMessage];
    
    return [NSString stringWithFormat:@"%@ [%@] [%@(line:%lu)] [%@] %@", timestamp, queueThreadLabel, logMessage->_file, (unsigned long)logMessage->_line, logMessage->_tag, logMessage->_message];
}

- (void)didAddToAppender:(id<SLLogAppender>)logger
{
    int32_t count = 0;
    if (@available(iOS 10, *)){
        count = 1 + atomic_fetch_add(&_atomicLoggerCount, 1); //atomic_fetch_add 返回的是原来的值。。
    }else{
        count = OSAtomicIncrement32(&_osAtomicLoggerCount);
    }
    
    NSAssert(count <= 1 || _mode == SLLogQueueFormatterModeShared, @"Can't reuse formatter with multiple loggers in non-shareable mode.");
}

- (void)willRemoveFromAppender:(id<SLLogAppender>)logger
{
    
    if (@available(iOS 10, *)){
        atomic_fetch_sub(&_atomicLoggerCount, 1);
    }else{
        OSAtomicDecrement32(&_osAtomicLoggerCount);
    }
}
@end
