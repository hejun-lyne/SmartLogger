//
//  SLLogFileAppender.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLAbstractLogAppender.h"
#import "SLLogFileInfo.h"
#import "SLLogFileManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface SLLogFileAppender : SLAbstractLogAppender
{
    SLLogFileInfo *_currentLogFileInfo;
}

- (instancetype)initWithLogFileManager:(id <SLLogFileManager>)logFileManager NS_DESIGNATED_INITIALIZER;


- (void)willLogMessage NS_REQUIRES_SUPER;
- (void)didLogMessage NS_REQUIRES_SUPER;
- (void)flush NS_REQUIRES_SUPER;

/**
 * Default return NO
 */
- (BOOL)shouldArchiveRecentLogFileInfo:(SLLogFileInfo *)recentLogFileInfo;

/**
 * Log file archive:
 *
 * `maximumFileSize`:
 *   日志文件不能超过该大小
 *
 * `rollingFrequency`
 *   `NSTimeInterval`, 当日志文件使用超过这个时间点时候会进行归档
 *
 * `doNotReuseLogFiles`
 *   YES - 每次应用启动都会创建新的日志文件xw
 **/
@property (readwrite, assign) unsigned long long maximumFileSize;
@property (readwrite, assign) NSTimeInterval rollingFrequency;
@property (readwrite, assign, atomic) BOOL doNotReuseLogFiles;
/// associated file manager
@property (strong, nonatomic, readonly) id<SLLogFileManager> logFileManager;
/// automatic add new line, default YES
@property (nonatomic, readwrite, assign) BOOL automaticallyAppendNewlineForCustomFormatters;


- (void)rollLogFileWithCompletionBlock:(nullable void (^)(void))completionBlock;

/**
 * If no file using, will return a new file info
 **/
@property (nonatomic, readonly, strong) SLLogFileInfo *currentLogFileInfo;
@end

NS_ASSUME_NONNULL_END
