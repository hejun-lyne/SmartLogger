//
//  SLLogFileAppender.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogFileAppender.h"
#import "SLCompressLogFileManager.h"
#import "SLLogger.h"
#import "SLLogMessage.h"
#import "SLLogFormatter.h"

#if TARGET_OS_IPHONE
/**
 * 在 iOS 创建日志文件的时候需要设置 NSFileProtectionKey = NSFileProtectionCompleteUnlessOpen.
 *
 * 但是加入 app 在后台启动，我们需要能够在后台打开文件，所以需要修改属性为 NSFileProtectionCompleteUntilFirstUserAuthentication
 */
BOOL sl_doesAppRunInBackground(void) {
    BOOL answer = NO;
    
    NSArray *backgroundModes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIBackgroundModes"];
    
    for (NSString *mode in backgroundModes) {
        if (mode.length > 0) {
            answer = YES;
            break;
        }
    }
    
    return answer;
}

#endif

unsigned long long const kSLDefaultLogMaxFileSize      = 1024 * 1024;      // 1 MB
NSTimeInterval     const kSLDefaultLogRollingFrequency = 60 * 60 * 24;     // 24 Hours
NSUInteger         const kSLDefaultLogMaxNumLogFiles   = 10;               // 50 Files
unsigned long long const kSLDefaultLogFilesDiskQuota   = 50 * 1024 * 1024; // 50 MB

@interface SLLogFileAppender () {
    __strong id <SLLogFileManager> _logFileManager;
    
    NSFileHandle *_currentLogFileHandle;
    
    dispatch_source_t _currentLogFileVnode;
    dispatch_source_t _rollingTimer;
    
    unsigned long long _maximumFileSize;
    NSTimeInterval _rollingFrequency;
}

- (void)rollLogFileNow;
- (void)maybeRollLogFileDueToAge;
- (void)maybeRollLogFileDueToSize;

@end

@implementation SLLogFileAppender

- (instancetype)init
{
    SLCompressLogFileManager *defaultLogFileManager = [[SLCompressLogFileManager alloc] init];
    return [self initWithLogFileManager:defaultLogFileManager];
}

- (instancetype)initWithLogFileManager:(id <SLLogFileManager>)aLogFileManager
{
    if ((self = [super init])) {
        _maximumFileSize = kSLDefaultLogMaxFileSize;
        _rollingFrequency = kSLDefaultLogRollingFrequency;
        _automaticallyAppendNewlineForCustomFormatters = YES;
        
        logFileManager = aLogFileManager;
    }
    
    return self;
}

- (void)dealloc
{
    [_currentLogFileHandle synchronizeFile];
    [_currentLogFileHandle closeFile];
    
    if (_currentLogFileVnode) {
        dispatch_source_cancel(_currentLogFileVnode);
        _currentLogFileVnode = NULL;
    }
    
    if (_rollingTimer) {
        dispatch_source_cancel(_rollingTimer);
        _rollingTimer = NULL;
    }
}

#pragma mark - Properties

@synthesize logFileManager;

- (unsigned long long)maximumFileSize
{
    __block unsigned long long result;
    
    dispatch_block_t block = ^{
        result = self->_maximumFileSize;
    };
    
    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");
    
    dispatch_queue_t globalLoggingQueue = [SLLogger globalLoggingQueue];
    
    dispatch_sync(globalLoggingQueue, ^{
        dispatch_sync(self.loggingQueue, block);
    });
    
    return result;
}

- (void)setMaximumFileSize:(unsigned long long)newMaximumFileSize
{
    dispatch_block_t block = ^{
        @autoreleasepool {
            self->_maximumFileSize = newMaximumFileSize;
            [self maybeRollLogFileDueToSize];
        }
    };
    
    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");
    
    dispatch_queue_t globalLoggingQueue = [SLLogger globalLoggingQueue];
    
    dispatch_async(globalLoggingQueue, ^{
        dispatch_async(self.loggingQueue, block);
    });
}

- (NSTimeInterval)rollingFrequency
{
    __block NSTimeInterval result;
    
    dispatch_block_t block = ^{
        result = self->_rollingFrequency;
    };
    
    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");
    
    dispatch_queue_t globalLoggingQueue = [SLLogger globalLoggingQueue];
    
    dispatch_sync(globalLoggingQueue, ^{
        dispatch_sync(self.loggingQueue, block);
    });
    
    return result;
}

- (void)setRollingFrequency:(NSTimeInterval)newRollingFrequency
{
    dispatch_block_t block = ^{
        @autoreleasepool {
            self->_rollingFrequency = newRollingFrequency;
            [self maybeRollLogFileDueToAge];
        }
    };
    
    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");
    
    dispatch_queue_t globalLoggingQueue = [SLLogger globalLoggingQueue];
    
    dispatch_async(globalLoggingQueue, ^{
        dispatch_async(self.loggingQueue, block);
    });
}

#pragma mark - File Rolling

- (void)scheduleTimerToRollLogFileDueToAge
{
    if (_rollingTimer) {
        dispatch_source_cancel(_rollingTimer);
        _rollingTimer = NULL;
    }
    
    if (_currentLogFileInfo == nil || _rollingFrequency <= 0.0) {
        return;
    }
    
    NSDate *logFileCreationDate = [_currentLogFileInfo creationDate];
    
    NSTimeInterval ti = [logFileCreationDate timeIntervalSinceReferenceDate];
    ti += _rollingFrequency;
    
    NSDate *logFileRollingDate = [NSDate dateWithTimeIntervalSinceReferenceDate:ti];
    
    NSLog(@"ATHLogFileAppender: scheduleTimerToRollLogFileDueToAge");
    
    NSLog(@"ATHLogFileAppender: logFileCreationDate: %@", logFileCreationDate);
    NSLog(@"ATHLogFileAppender: logFileRollingDate : %@", logFileRollingDate);
    
    _rollingTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.loggingQueue);
    
    dispatch_source_set_event_handler(_rollingTimer, ^{ @autoreleasepool {
        [self maybeRollLogFileDueToAge];
    } });
    
    uint64_t delay = (uint64_t)([logFileRollingDate timeIntervalSinceNow] * (NSTimeInterval) NSEC_PER_SEC);
    dispatch_time_t fireTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay);
    
    dispatch_source_set_timer(_rollingTimer, fireTime, DISPATCH_TIME_FOREVER, 1ull * NSEC_PER_SEC);
    dispatch_resume(_rollingTimer);
}

- (void)rollLogFile
{
    [self rollLogFileWithCompletionBlock:nil];
}

- (void)rollLogFileWithCompletionBlock:(void (^)(void))completionBlock
{
    dispatch_block_t block = ^{
        @autoreleasepool {
            [self rollLogFileNow];
            
            if (completionBlock) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    completionBlock();
                });
            }
        }
    };
    
    if ([self isOnInternalLoggerQueue]) {
        block();
    } else {
        dispatch_queue_t globalLoggingQueue = [SLLogger globalLoggingQueue];
        NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
        
        dispatch_async(globalLoggingQueue, ^{
            dispatch_async(self.loggingQueue, block);
        });
    }
}

- (void)rollLogFileNow
{
    NSLog(@"ATHLogFileAppender: rollLogFileNow");
    
    if (_currentLogFileHandle == nil) {
        return;
    }
    
    [_currentLogFileHandle synchronizeFile];
    [_currentLogFileHandle closeFile];
    _currentLogFileHandle = nil;
    
    _currentLogFileInfo.isArchived = YES;
    
    if ([logFileManager respondsToSelector:@selector(didRollAndArchiveLogFile:)]) {
        [logFileManager didRollAndArchiveLogFile:(_currentLogFileInfo.filePath)];
    }
    
    _currentLogFileInfo = nil;
    
    if (_currentLogFileVnode) {
        dispatch_source_cancel(_currentLogFileVnode);
        _currentLogFileVnode = NULL;
    }
    
    if (_rollingTimer) {
        dispatch_source_cancel(_rollingTimer);
        _rollingTimer = NULL;
    }
}

- (void)maybeRollLogFileDueToAge
{
    if (_rollingFrequency > 0.0 && _currentLogFileInfo.age >= _rollingFrequency) {
        NSLog(@"ATHLogFileAppender: Rolling log file due to age...");
        
        [self rollLogFileNow];
    } else {
        [self scheduleTimerToRollLogFileDueToAge];
    }
}

- (void)maybeRollLogFileDueToSize
{
    // logMessage 会调用这个方法.
    // Keep it FAST.
    
    // Note: 直接访问
    
    if (_maximumFileSize > 0) {
        unsigned long long fileSize = [_currentLogFileHandle offsetInFile];
        
        if (fileSize >= _maximumFileSize) {
            NSLog(@"ATHLogFileAppender: Rolling log file due to size (%qu)...", fileSize);
            
            [self rollLogFileNow];
        }
    }
}

#pragma mark - File Logging

- (SLLogFileInfo *)currentLogFileInfo
{
    if (_currentLogFileInfo == nil) {
        NSArray *sortedLogFileInfos = [logFileManager sortedLogFileInfos];
        
        if ([sortedLogFileInfos count] > 0) {
            SLLogFileInfo *mostRecentLogFileInfo = sortedLogFileInfos[0];
            
            BOOL shouldArchiveMostRecent = NO;
            
            if (mostRecentLogFileInfo.isArchived) {
                shouldArchiveMostRecent = NO;
            } else if ([self shouldArchiveRecentLogFileInfo:mostRecentLogFileInfo]) {
                shouldArchiveMostRecent = YES;
            } else if (_maximumFileSize > 0 && mostRecentLogFileInfo.fileSize >= _maximumFileSize) {
                shouldArchiveMostRecent = YES;
            } else if (_rollingFrequency > 0.0 && mostRecentLogFileInfo.age >= _rollingFrequency) {
                shouldArchiveMostRecent = YES;
            }
            
#if TARGET_OS_IPHONE
            
            if (!_doNotReuseLogFiles && sl_doesAppRunInBackground()) {
                NSFileProtectionType key = mostRecentLogFileInfo.fileAttributes[NSFileProtectionKey];
                
                if ([key length] > 0 && !([key isEqualToString:NSFileProtectionCompleteUntilFirstUserAuthentication] || [key isEqualToString:NSFileProtectionNone])) {
                    shouldArchiveMostRecent = YES;
                }
            }
            
#endif
            
            if (!_doNotReuseLogFiles && !mostRecentLogFileInfo.isArchived && !shouldArchiveMostRecent) {
                NSLog(@"ATHLogFileAppender: Resuming logging with file %@", mostRecentLogFileInfo.fileName);
                
                _currentLogFileInfo = mostRecentLogFileInfo;
            } else {
                if (shouldArchiveMostRecent) {
                    mostRecentLogFileInfo.isArchived = YES;
                    
                    if ([logFileManager respondsToSelector:@selector(didArchiveLogFile:)]) {
                        [logFileManager didArchiveLogFile:(mostRecentLogFileInfo.filePath)];
                    }
                }
            }
        }
        
        if (_currentLogFileInfo == nil) {
            NSString *currentLogFilePath = [logFileManager createNewLogFile];
            
            _currentLogFileInfo = [[SLLogFileInfo alloc] initWithFilePath:currentLogFilePath];
        }
    }
    
    return _currentLogFileInfo;
}

- (NSFileHandle *)currentLogFileHandle
{
    if (_currentLogFileHandle == nil) {
        NSString *logFilePath = [[self currentLogFileInfo] filePath];
        
        _currentLogFileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
        [_currentLogFileHandle seekToEndOfFile];
        
        if (_currentLogFileHandle) {
            [self scheduleTimerToRollLogFileDueToAge];
            
            // 需要监控当前日志文件
            _currentLogFileVnode = dispatch_source_create(
                                                          DISPATCH_SOURCE_TYPE_VNODE,
                                                          (uintptr_t)[_currentLogFileHandle fileDescriptor],
                                                          DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME,
                                                          self.loggingQueue
                                                          );
            
            dispatch_source_set_event_handler(_currentLogFileVnode, ^{ @autoreleasepool {
                NSLog(@"ATHLogFileAppender: Current logfile was moved. Rolling it and creating a new one");
                [self rollLogFileNow];
            } });
            
#if !OS_OBJECT_USE_OBJC
            dispatch_source_t vnode = _currentLogFileVnode;
            dispatch_source_set_cancel_handler(_currentLogFileVnode, ^{
                dispatch_release(vnode);
            });
#endif
            
            dispatch_resume(_currentLogFileVnode);
        }
    }
    
    return _currentLogFileHandle;
}

#pragma mark - ATHLogger Protocol

static int exception_count = 0;
- (void)logMessage:(SLLogMessage *)logMessage
{
    NSString *message = logMessage->_message;
    BOOL isFormatted = NO;
    
    if (_logFormatter) {
        message = [_logFormatter formatLogMessage:logMessage];
        isFormatted = message != logMessage->_message;
    }
    
    if (message) {
        if ((!isFormatted || _automaticallyAppendNewlineForCustomFormatters) &&
            (![message hasSuffix:@"\n"])) {
            message = [message stringByAppendingString:@"\n"];
        }
        
        NSData *logData = [message dataUsingEncoding:NSUTF8StringEncoding];
        
        @try {
            [self willLogMessage];
            
            [[self currentLogFileHandle] writeData:logData];
            
            [self didLogMessage];
        } @catch (NSException *exception) {
            exception_count++;
            
            if (exception_count <= 10) {
                NSLog(@"ATHLogFileAppender.logMessage: %@", exception);
                
                if (exception_count == 10) {
                    NSLog(@"ATHLogFileAppender.logMessage: Too many exceptions -- will not log any more of them.");
                }
            }
        }
    }
}

- (void)willLogMessage
{
    
}

- (void)didLogMessage
{
    [self maybeRollLogFileDueToSize];
}

- (BOOL)shouldArchiveRecentLogFileInfo:(SLLogFileInfo *)recentLogFileInfo
{
    return NO;
}

- (void)willRemoveLogger
{
    [self rollLogFileNow];
}

- (NSString *)appenderName
{
    return [self loggerName];
}

- (NSString *)loggerName
{
    return @"com.yy.athlog.fileLogger";
}

- (void)flush
{
    [_currentLogFileHandle synchronizeFile];
}
@end
