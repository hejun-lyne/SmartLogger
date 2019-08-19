//
//  SLLogFormatter.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#ifndef SLLogFormatter_h
#define SLLogFormatter_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SLLogMessage;
@protocol SLLogAppender;
@protocol SLLogFormatter <NSObject>
@required

- (NSString * __nullable)formatLogMessage:(SLLogMessage *)logMessage;

@optional

- (void)didAddToAppender:(id <SLLogAppender>)logger;
- (void)didAddToAppender:(id <SLLogAppender>)appender inQueue:(dispatch_queue_t)queue;
- (void)willRemoveFromAppender:(id <SLLogAppender>)logger;

@end

NS_ASSUME_NONNULL_END

#endif /* SLLogFormatter_h */
