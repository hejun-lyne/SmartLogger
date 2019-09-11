//
//  SLAbstractLogAppender.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogAppender.h"

NS_ASSUME_NONNULL_BEGIN

@interface SLAbstractLogAppender : NSObject<SLLogAppender>
{
@public
    id <SLLogFormatter> _logFormatter;
    dispatch_queue_t _loggingQueue;
}

@property (nonatomic, strong, nullable) id <SLLogFormatter> logFormatter;
@property (nonatomic, strong) dispatch_queue_t loggingQueue;
@property (nonatomic, strong, readonly) NSString *appenderName;

// thread safety
@property (nonatomic, readonly, getter=isOnGlobalLoggingQueue)  BOOL onGlobalLoggingQueue;
@property (nonatomic, readonly, getter=isOnInternalLoggerQueue) BOOL onInternalLoggerQueue;
@end

NS_ASSUME_NONNULL_END
