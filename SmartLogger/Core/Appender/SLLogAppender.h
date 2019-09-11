//
//  SLLogAppender.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#ifndef SLLogAppender_h
#define SLLogAppender_h

#import <Foundation/Foundation.h>

@class SLLogMessage;
@protocol SLLogFormatter;

@protocol SLLogAppender <NSObject>
/// formatter, should have default implementation
@property (nonatomic, strong) id <SLLogFormatter> logFormatter;
/// exclusive logging queue
@property (nonatomic, strong, readonly) dispatch_queue_t loggingQueue;
/// for debugging
@property (nonatomic, readonly) NSString *appenderName;

- (void)logMessage:(SLLogMessage *)logMessage;

@optional

- (void)didAddAppender;
- (void)didAddAppenderInQueue:(dispatch_queue_t)queue;
- (void)willRemoveAppender;

/// flush all queued logs
- (void)flush;

@end

#endif /* SLLogAppender_h */
