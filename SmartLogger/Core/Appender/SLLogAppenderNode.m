//
//  SLLogAppenderNode.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogAppenderNode.h"

@implementation SLLogAppenderNode

- (instancetype)initWithAppender:(id <SLLogAppender>)appender loggingQueue:(dispatch_queue_t)loggingQueue level:(SLLogLevel)level
{
    if ((self = [super init])) {
        _appender = appender;
        
        if (loggingQueue) {
            _loggingQueue = loggingQueue;
        }
        
        _level = level;
    }
    return self;
}

+ (SLLogAppenderNode *)nodeWithAppender:(id<SLLogAppender>)appender loggingQueue:(dispatch_queue_t)loggingQueue level:(SLLogLevel)level
{
    return [[SLLogAppenderNode alloc] initWithAppender:appender loggingQueue:loggingQueue level:level];
}

@end
