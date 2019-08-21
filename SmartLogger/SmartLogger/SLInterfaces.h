//
//  SLInterfaces.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/15.
//  Copyright © 2019 Hejun. All rights reserved.
//

#ifndef SLInterfaces_h
#define SLInterfaces_h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Log flags for tagging logs
typedef NS_OPTIONS(NSUInteger, SLLogFlag){
    SLLogFlagError      = (1 << 0),
    SLLogFlagWarning    = (1 << 1),
    SLLogFlagInfo       = (1 << 2),
    SLLogFlagDebug      = (1 << 4)
};

/// Log levels for filtering logs
typedef NS_ENUM(NSUInteger, SLLogLevel){
    SLLogLevelOff       = 0,
    SLLogLevelError     = (SLLogFlagError),
    SLLogLevelWarning   = (SLLogLevelError | SLLogFlagWarning),
    SLLogLevelInfo      = (SLLogLevelWarning | SLLogFlagInfo),
    SLLogLevelDebug     = (SLLogLevelInfo | SLLogFlagDebug),
    SLLogLevelAll       = NSUIntegerMax
};

/**
 * File logger configuration
 * kSLDefaultLogMaxFileSize      = 1024 * 1024;      // 1 MB
 * kSLDefaultLogRollingFrequency = 60 * 60 * 24;     // 24 Hours
 * kSLDefaultLogMaxNumLogFiles   = 10;               // 50 Files
 * kSLDefaultLogFilesDiskQuota   = 50 * 1024 * 1024; // 50 MB
 */
typedef struct SLFileLoggerConfig {
    /**
     * 允许最多的日志文件数量，0-表示使用默认
     */
    unsigned int maxNumberOfFiles;
    /**
     * 允许单个日志文件的最大尺寸，0-表示使用默认
     * (in bytes)
     */
    unsigned long long maxFileSize;
    /**
     * 允许占用的磁盘空间大小，0-表示使用默认
     * optional
     * (in bytes)
     */
    unsigned long long diskQuota;
    /**
     * 指定日志文件目录，传空则由组件自行决定
     */
    const char * _Nullable directory;
    /**
     * 日志文件的归档频率，比如24小时
     * optional
     * (in seconds)
     */
    NSTimeInterval rollingFrequency;
    /**
     * 设定输出的日志级别, 0 == ATHLogLevelAll
     */
    SLLogLevel level;
    
} SLFileLoggerConfig;

/// Compress block
typedef NSString * _Nullable(^SLLogArchiveCompressBlock)(NSString *logFile);

@protocol SLInterfaces <NSObject>
/// In release will stop tty appender
@property (class, nonatomic, assign) BOOL isRelease;
/// Directory storing logs
@property (nonatomic, class, readonly) NSString *logsDirectory;
/// All data files
@property (nonatomic, class, readonly) NSArray<NSString *> *logFiles;
/// Log file compress block
@property (class, nonatomic, copy) SLLogArchiveCompressBlock compressBlock;

/**
 * Config file logger
 *  @param fileLoggerConfig Configuration
 *  @see SLFileLoggerConfig
 */
+ (void)setFileLoggerConfig:(SLFileLoggerConfig)fileLoggerConfig;

/**
 * Appending log message
 * Not for directly usage
 *  @param async        YES - async write log, NO - sync write log
 *  @param level        level
 *  @param flag         flag
 *  @param file         source file
 *  @param function     which function
 *  @param line         line
 *  @param tag          custom tag
 *  @param format       variables
 */
+ (void)log:(BOOL)async
      level:(SLLogLevel)level
       flag:(SLLogFlag)flag
       file:(nonnull const char *)file
   function:(nonnull const char *)function
       line:(NSUInteger)line
        tag:(id __nullable)tag
     format:(NSString *_Nonnull)format, ... NS_FORMAT_FUNCTION(8,9);

/**
 * Logging without format
 *  @param async        YES - async write log, NO - sync write log
 *  @param tag          custom tag
 *  @param message      Logging message
 */
+ (void)directlog:(BOOL)async
              tag:(id)tag
          message:(NSString *)message;

/**
 * flush all cached logs
 **/
+ (void)flush;

/**
 * Toggle log file compressing swith.
 * Call while need to retrieve all log files to upload.
 *  @param on   Switch status
 */
+ (void)toggleLogCompress:(BOOL)on;

@end

NS_ASSUME_NONNULL_END

#endif /* SLCommonDefines_h */
