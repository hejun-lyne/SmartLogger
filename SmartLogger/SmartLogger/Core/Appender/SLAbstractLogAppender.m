//
//  SLAbstractLogAppender.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLAbstractLogAppender.h"
#import "SLLogMessage.h"
#import "SLLogFormatter.h"
#import "SLLogger.h"

@implementation SLAbstractLogAppender

- (instancetype)init
{
    if ((self = [super init])) {
        const char *loggerQueueName = NULL;
        
        if ([self respondsToSelector:@selector(appenderName)]) {
            loggerQueueName = [[self appenderName] UTF8String];
        }
        
        _loggingQueue = dispatch_queue_create(loggerQueueName, NULL);
        
        void *key = (__bridge void *)self;
        void *nonNullValue = (__bridge void *)self;
        dispatch_queue_set_specific(_loggingQueue, key, nonNullValue, NULL);
    }
    
    return self;
}

- (void)logMessage:(SLLogMessage * __attribute__((unused)))logMessage
{
    // Override me
}

- (id <SLLogFormatter>)logFormatter
{
    // This method must be thread safe and intuitive.
    
    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");
    
    dispatch_queue_t globalLoggingQueue = [SLLogger globalLoggingQueue];
    
    __block id <SLLogFormatter> result;
    
    dispatch_sync(globalLoggingQueue, ^{
        dispatch_sync(self->_loggingQueue, ^{
            result = self->_logFormatter;
        });
    });
    
    return result;
}

- (void)setLogFormatter:(id <SLLogFormatter>)logFormatter
{
    // The design of this method is documented extensively in the logFormatter message (above in code).
    
    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");
    
    dispatch_block_t block = ^{
        @autoreleasepool {
            if (self->_logFormatter != logFormatter) {
                if ([self->_logFormatter respondsToSelector:@selector(willRemoveFromAppender:)]) {
                    [self->_logFormatter willRemoveFromAppender:self];
                }
                
                self->_logFormatter = logFormatter;
                
                if ([self->_logFormatter respondsToSelector:@selector(didAddToAppender:inQueue:)]) {
                    [self->_logFormatter didAddToAppender:self inQueue:self->_loggingQueue];
                } else if ([self->_logFormatter respondsToSelector:@selector(didAddToAppender:)]) {
                    [self->_logFormatter didAddToAppender:self];
                }
            }
        }
    };
    
    dispatch_queue_t globalLoggingQueue = [SLLogger globalLoggingQueue];
    dispatch_async(globalLoggingQueue, ^{
        dispatch_async(self->_loggingQueue, block);
    });
}

- (dispatch_queue_t)loggingQueue
{
    return _loggingQueue;
}

- (NSString *)appenderName
{
    return NSStringFromClass([self class]);
}

- (BOOL)isOnGlobalLoggingQueue
{
    return (dispatch_get_specific(SLGlobalLoggingQueueIdentityKey) != NULL);
}

- (BOOL)isOnInternalLoggerQueue
{
    void *key = (__bridge void *)self;
    
    return (dispatch_get_specific(key) != NULL);
}
@end
