//
//  SLLogFileManager.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#ifndef SLLogFileManager_h
#define SLLogFileManager_h

#import <Foundation/Foundation.h>

// Default configurations
extern unsigned long long const kSLDefaultLogMaxFileSize;
extern NSTimeInterval     const kSLDefaultLogRollingFrequency;
extern NSUInteger         const kSLDefaultLogMaxNumLogFiles;
extern unsigned long long const kSLDefaultLogFilesDiskQuota;
extern BOOL sl_doesAppRunInBackground(void);

@class SLLogFileInfo;

@protocol SLLogFileManager <NSObject>
@required

// properties

/**
 * 0 - not limited
 **/
@property (readwrite, assign, atomic) NSUInteger maximumNumberOfLogFiles;

/**
 * disk quota
 **/
@property (readwrite, assign, atomic) unsigned long long logFilesDiskQuota;

// Public methods

/**
 * directory
 */
@property (nonatomic, readonly, copy) NSString *logsDirectory;

/**
 * all log files
 **/
@property (nonatomic, readonly, strong) NSArray<NSString *> *unsortedLogFilePaths;

/**
 * all log file names
 **/
@property (nonatomic, readonly, strong) NSArray<NSString *> *unsortedLogFileNames;

/**
 * all log file info
 **/
@property (nonatomic, readonly, strong) NSArray<SLLogFileInfo *> *unsortedLogFileInfos;

/**
 * all sorted log files
 **/
@property (nonatomic, readonly, strong) NSArray<NSString *> *sortedLogFilePaths;

/**
 * all sorted log file names
 **/
@property (nonatomic, readonly, strong) NSArray<NSString *> *sortedLogFileNames;

/**
 * all sorted log file info
 **/
@property (nonatomic, readonly, strong) NSArray<SLLogFileInfo *> *sortedLogFileInfos;

// Private methods

- (NSString *)createNewLogFile;

@optional

- (void)didArchiveLogFile:(NSString *)logFilePath;
- (void)didRollAndArchiveLogFile:(NSString *)logFilePath;

@end

#endif /* SLLogFileManager_h */
