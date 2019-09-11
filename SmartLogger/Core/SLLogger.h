//
//  SLLogger.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLInterfaces.h"
#import "SLLogAppender.h"

NS_ASSUME_NONNULL_BEGIN

static void * const SLGlobalLoggingQueueIdentityKey = (void *)&SLGlobalLoggingQueueIdentityKey;

@interface SLLogger : NSObject<SLInterfaces>
/**
 * Global logging queue
 **/
@property (class, nonatomic, strong, readonly) dispatch_queue_t globalLoggingQueue;

/**
 * Shared instance
 *
 */
+ (instancetype)shared;

/**
 * Add new appender
 *
 * Equal to: `[ATHLogger addAppender:appender withLogLevel:ATHLogLevelAll]`.
 **/
+ (void)addAppender:(id <SLLogAppender>)appender;

/**
 * Add new appender and assign level
 * 比如：如果希望记录除了 verbose & debug 以外的消息:
 * `((DDLogLevelAll ^ DDLogLevelVerbose) | DDLogLevelInfo)`
 **/
+ (void)addAppender:(id <SLLogAppender>)appender withLevel:(SLLogLevel)level;

/**
 * Remove appender
 */
+ (void)removeAppender:(id <SLLogAppender>)logger;

/**
 * Remove all appender
 */
+ (void)removeAllAppenders;

@end

NS_ASSUME_NONNULL_END
