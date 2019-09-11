//
//  SLLogAppenderNode.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogAppender.h"
#import "SLInterfaces.h"

NS_ASSUME_NONNULL_BEGIN

@interface SLLogAppenderNode : NSObject
{
@public
    id <SLLogAppender> _appender;
    SLLogLevel _level;
    dispatch_queue_t _loggingQueue;
}

@property (nonatomic, readonly) id <SLLogAppender> appender;
@property (nonatomic, readonly) SLLogLevel level;
@property (nonatomic, readonly) dispatch_queue_t loggingQueue;

+ (SLLogAppenderNode *)nodeWithAppender:(id <SLLogAppender>)appender
                         loggingQueue:(dispatch_queue_t)loggingQueue
                                level:(SLLogLevel)level;
@end

NS_ASSUME_NONNULL_END
