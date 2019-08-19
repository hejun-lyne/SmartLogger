//
//  SLLogger.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogger.h"
#import "SLLogFileAppender.h"
#import "SLCompressLogFileManager.h"
#import "SLLogFileAppender.h"
#import "SLLogAppenderNode.h"
#import "SLTTYLogAppender.h"
#import "SLLogQueueFormatter.h"
#import "SLLogMessage.h"

@interface SLLogger()
@property (nonatomic, strong) NSMutableArray *appenders;
@property (nonatomic, weak) SLLogFileAppender *fileAppender;
@property (nonatomic, copy) SLLogArchiveCompressBlock archiveCompressBlock;
@end

@implementation SLLogger
{
    /// Caching message, because all threads will suspended while crash,
    /// So we can't only using dispatch_queue for caching.
    NSMutableArray<SLLogMessage *> *messagesQueue;
    NSLock *queueLock;
}
@dynamic logsDirectory, logFiles, fileLoggerConfig, compressBlock, isRelease;

+ (NSString *)logsDirectory
{
    id <SLLogFileManager> fileManager = SLLogger.shared.fileAppender.logFileManager;
    return fileManager.logsDirectory;
}

+ (NSArray<NSString *> *)logFiles
{
    id <SLLogFileManager> fileManager = SLLogger.shared.fileAppender.logFileManager;
    return fileManager.unsortedLogFilePaths;
}

+ (void)setFileLoggerConfig:(SLFileLoggerConfig)fileLoggerConfig
{
    SLLogger *logger = [self shared];
    // make a new file appender
    [logger removeAppender:logger.fileAppender];
    logger.fileAppender = nil;
    
    NSString *logDirectory = fileLoggerConfig.directory ? [NSString stringWithUTF8String:fileLoggerConfig.directory] : nil;
    SLCompressLogFileManager *fm = [[SLCompressLogFileManager alloc] initWithLogsDirectory:logDirectory];
    fm.maximumNumberOfLogFiles = fileLoggerConfig.maxNumberOfFiles;
    fm.logFilesDiskQuota = fileLoggerConfig.diskQuota;
    fm.compressBlock = logger.archiveCompressBlock;
    
    SLLogFileAppender *fileAppender = [[SLLogFileAppender alloc] initWithLogFileManager:fm];
    fileAppender.maximumFileSize = fileLoggerConfig.maxFileSize;
    fileAppender.rollingFrequency = fileLoggerConfig.rollingFrequency;
    
    if (fileLoggerConfig.level <= 0) {
        [logger addAppender:fileAppender];
    } else {
        [logger addAppender:fileAppender withLevel:fileLoggerConfig.level];
    }
    logger.fileAppender = fileAppender;
}

+ (void)flush
{
    SLLogger *logger = [self shared];
    
    // flush queue first
    [logger->queueLock lock];
    NSArray *logs = [logger->messagesQueue copy];
    [logger->queueLock unlock];
    
    for (SLLogMessage *logMessage in logs) {
        for (SLLogAppenderNode *appenderNode in logger.appenders) {
            if (!(logMessage->_flag & appenderNode->_level)) {
                continue;
            }
            @autoreleasepool {
                [appenderNode->_appender logMessage:logMessage];
            }
        }
    }
    
    // flush appenders, eg. close file
    [logger flushAppenders];
}

+ (void)log:(BOOL)asynchronous
      level:(SLLogLevel)level
       flag:(SLLogFlag)flag
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
        tag:(NSString *)tag
     format:(NSString *)format, ...
{
    va_list args;
    
    if (format) {
        va_start(args, format);
        
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        
        va_end(args);
        
        va_start(args, format);
        
        [[self shared] log:asynchronous
                           message:message
                             level:level
                              flag:flag
                              file:file
                          function:function
                              line:line
                               tag:tag];
        
        va_end(args);
    }
}

+ (void)directlog:(BOOL)async tag:(id)tag message:(NSString *)message
{
    [self.shared directlog:async tag:tag message:message];
}

- (void)startDefaultAppenders
{
    // Only in case of empty appenders.
    if (_appenders.count > 0) { return; }
    
    // Create a tty appender
    SLTTYLogAppender *ttyLogger = [[SLTTYLogAppender alloc] init];
    ttyLogger.logFormatter = [[SLLogQueueFormatter alloc] initWithMode:SLLogQueueFormatterModeAlone];
    [self addAppender:ttyLogger];
}

#pragma mark - ATHLogger Implementation

static dispatch_queue_t _loggingQueue;
static dispatch_group_t _loggingGroup;
#define _MAX_QUEUE_SIZE 1000 // Should not exceed INT32_MAX
static dispatch_semaphore_t _queueSemaphore;

// Minor optimization for uniprocessor machines
static NSUInteger _numProcessors;

+ (instancetype)shared
{
    static SLLogger *s_logger = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_logger = [SLLogger new];
    });
    return s_logger;
}

+ (void)initialize
{
    
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _loggingQueue = dispatch_queue_create("smartlogger.logger", NULL);
        _loggingGroup = dispatch_group_create();
        
        void *nonNullValue = GlobalLoggingQueueIdentityKey; // Whatever, just not null
        dispatch_queue_set_specific(_loggingQueue, GlobalLoggingQueueIdentityKey, nonNullValue, NULL);
        
        _queueSemaphore = dispatch_semaphore_create(_MAX_QUEUE_SIZE);
        _numProcessors = MAX([NSProcessInfo processInfo].processorCount, (NSUInteger) 1);
    });
    
#if DEBUG
    [self setIsRelease:NO];
#else
    [self setIsRelease:YES];
#endif
    [[self shared] startDefaultAppenders];
}


- (id)init
{
    if (self = [super init]) {
        messagesQueue = [NSMutableArray arrayWithCapacity:50];
        
        self.appenders = [[NSMutableArray alloc] initWithCapacity:4];
        
#if TARGET_OS_IOS
        NSString *notificationName = @"UIApplicationWillTerminateNotification";
#else
        NSString *notificationName = nil;
        // On Command Line Tool apps AppKit may not be avaliable
#ifdef NSAppKitVersionNumber10_0
        if (NSApp) {
            notificationName = @"NSApplicationWillTerminateNotification";
        }
#endif
        if (!notificationName) {
            // If there is no NSApp -> we are running Command Line Tool app.
            // In this case terminate notification wouldn't be fired, so we use workaround.
            atexit_b (^{
                [self applicationWillTerminate:nil];
            });
        }
#endif /* if TARGET_OS_IOS */
        
        if (notificationName) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(applicationWillTerminate:)
                                                         name:notificationName
                                                       object:nil];
        }
    }
    
    return self;
}

+ (dispatch_queue_t)globalLoggingQueue
{
    return _loggingQueue;
}

#pragma mark - Notifications

- (void)applicationWillTerminate:(NSNotification * __attribute__((unused)))notification
{
    [self flushAppenders];
}

#pragma mark - Logger Management

+ (void)setIsRelease:(BOOL)isRelease
{
    SLTTYLogAppender.enable = !isRelease;
}

+ (void)setCompressBlock:(SLLogArchiveCompressBlock)compressBlock
{
    SLLogger *logger = [SLLogger shared];
    logger.archiveCompressBlock = compressBlock;
    NSObject<SLLogFileManager> *fm = logger.fileAppender.logFileManager;
    if ([fm isKindOfClass:SLCompressLogFileManager.class]) {
        ((SLCompressLogFileManager *)fm).compressBlock = compressBlock;
    }
}

+ (void)toggleLogCompress:(BOOL)on
{
    SLLogger *logger = [SLLogger shared];
    NSObject<SLLogFileManager> *fm = logger.fileAppender.logFileManager;
    if ([fm isKindOfClass:SLCompressLogFileManager.class]) {
        ((SLCompressLogFileManager *)fm).on = on;
    }
}

+ (BOOL)isRelease
{
    return SLTTYLogAppender.enable;
}

+ (SLLogArchiveCompressBlock)compressBlock
{
    return SLLogger.shared.archiveCompressBlock;
}

+ (void)addAppender:(id<SLLogAppender>)appender
{
    [self.shared addAppender:appender];
}

- (void)addAppender:(id<SLLogAppender>)appender
{
    [self addAppender:appender withLevel:SLLogLevelAll];
}

+ (void)addAppender:(id<SLLogAppender>)appender withLevel:(SLLogLevel)level
{
    [self.shared addAppender:appender withLevel:level];
}

- (void)addAppender:(id<SLLogAppender>)appender withLevel:(SLLogLevel)level
{
    if (!appender) {
        return;
    }
    if (appender.logFormatter == nil) {
        appender.logFormatter = [[SLLogQueueFormatter alloc] initWithMode:SLLogQueueFormatterModeAlone];
    }
    dispatch_async(_loggingQueue, ^{ @autoreleasepool {
        [self mf_addAppender:appender level:level];
    } });
}

+ (void)removeAppender:(id<SLLogAppender>)appender
{
    [self.shared removeAppender:appender];
}

- (void)removeAppender:(id<SLLogAppender>)appender
{
    if (!appender) {
        return;
    }
    
    dispatch_async(_loggingQueue, ^{ @autoreleasepool {
        [self mf_removeAppender:appender];
    } });
}

+ (void)removeAllAppenders
{
    [self.shared removeAllAppenders];
}

- (void)removeAllAppenders
{
    dispatch_async(_loggingQueue, ^{ @autoreleasepool {
        [self mf_removeAllAppenders];
    } });
}

+ (NSArray<id<SLLogAppender>> *)allAppenders
{
    return [self.shared allAppenders];
}

- (NSArray<id<SLLogAppender>> *)allAppenders
{
    __block NSArray *theAppenders;
    
    dispatch_sync(_loggingQueue, ^{ @autoreleasepool {
        theAppenders = [self mf_allAppenders];
    } });
    
    return theAppenders;
}

#pragma mark - Master Logging

- (void)queueLogMessage:(SLLogMessage *)logMessage asynchronously:(BOOL)asyncFlag
{
    dispatch_block_t logBlock = ^{
        dispatch_semaphore_wait(_queueSemaphore, DISPATCH_TIME_FOREVER);
        @autoreleasepool {
            [self->queueLock lock];
            SLLogMessage *mf_msg = [self->messagesQueue lastObject];
            [self->messagesQueue removeObject:mf_msg];
            [self->queueLock unlock];
            [self mf_log:mf_msg];
        }
    };
    
    if (asyncFlag) {
        [self->queueLock lock];
        [self->messagesQueue addObject:logMessage];
        [self->queueLock unlock];
        dispatch_async(_loggingQueue, logBlock);
    } else {
        dispatch_sync(_loggingQueue, logBlock);
    }
}

#define __FILE_NAME__(file) (ATHExtractFileNameWithoutExtension(file, NO))

- (void)log:(BOOL)asynchronous
    message:(NSString *)message
      level:(SLLogLevel)level
       flag:(SLLogFlag)flag
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
        tag:(NSString *)tag
{
    NSString *funcName = [NSString stringWithFormat:@"%s", function];
    SLLogMessage *logMessage = [[SLLogMessage alloc] initWithMessage:message
                                                                 level:level
                                                                  flag:flag
                                                                  file:__FILE_NAME__(file)
                                                              function:funcName
                                                                  line:line
                                                                   tag:tag
                                                             timestamp:nil];
    
    [self queueLogMessage:logMessage asynchronously:asynchronous];
}

- (void)directlog:(BOOL)asynchronous
              tag:(id)tag
          message:(NSString *)message
{
    SLLogMessage *logMessage = [[SLLogMessage alloc] initWithMessage:message tag:tag];
    [self queueLogMessage:logMessage asynchronously:asynchronous];
}

- (void)flushAppenders
{
    dispatch_sync(_loggingQueue, ^{ @autoreleasepool {
        [self mf_flushAppenders];
    } });
}

#pragma mark - Logging Thread

- (void)mf_addAppender:(id <SLLogAppender>)appender level:(SLLogLevel)level
{
    for (SLLogAppenderNode* node in self.appenders) {
        if (node->_appender == appender
            && node->_level == level) {
            return;
        }
    }
    
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");
    
    dispatch_queue_t loggingQueue = NULL;
    
    if ([appender respondsToSelector:@selector(loggingQueue)]) {
        loggingQueue = [appender loggingQueue];
    }
    
    if (loggingQueue == nil) {
        const char *loggingQueueName = NULL;
        if ([appender respondsToSelector:@selector(appenderName)]) {
            loggingQueueName = [[appender appenderName] UTF8String];
        }
        loggingQueue = dispatch_queue_create(loggingQueueName, NULL);
    }
    
    SLLogAppenderNode *node = [SLLogAppenderNode nodeWithAppender:appender loggingQueue:loggingQueue level:level];
    [self.appenders addObject:node];
    
    if ([appender respondsToSelector:@selector(didAddAppenderInQueue:)]) {
        dispatch_async(node->_loggingQueue, ^{ @autoreleasepool {
            [appender didAddAppenderInQueue:node->_loggingQueue];
        } });
    } else if ([appender respondsToSelector:@selector(didAddAppender)]) {
        dispatch_async(node->_loggingQueue, ^{ @autoreleasepool {
            [appender didAddAppender];
        } });
    }
}

- (void)mf_removeAppender:(id <SLLogAppender>)appender
{
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");
    
    SLLogAppenderNode *appenderNode = nil;
    for (SLLogAppenderNode *node in self.appenders) {
        if (node->_appender == appender) {
            appenderNode = node;
            break;
        }
    }
    
    if (appenderNode == nil) {
        NSLog(@"Request to remove appender which wasn't added");
        return;
    }
    
    // Notify logger
    if ([appender respondsToSelector:@selector(willRemoveAppender)]) {
        dispatch_async(appenderNode->_loggingQueue, ^{ @autoreleasepool {
            [appender willRemoveAppender];
        } });
    }
    
    // Remove from loggers array
    [self.appenders removeObject:appenderNode];
}

- (void)mf_removeAllAppenders
{
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");
    
    for (SLLogAppenderNode *loggerAppender in self.appenders) {
        if ([loggerAppender->_appender respondsToSelector:@selector(willRemoveAppender)]) {
            dispatch_async(loggerAppender->_loggingQueue, ^{ @autoreleasepool {
                [loggerAppender->_appender willRemoveAppender];
            } });
        }
    }
    
    [self.appenders removeAllObjects];
}

- (NSArray *)mf_allAppenders
{
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");
    
    NSMutableArray *theAppenders = [NSMutableArray new];
    
    for (SLLogAppenderNode *appenderNode in self.appenders) {
        [theAppenders addObject:appenderNode->_appender];
    }
    
    return [theAppenders copy];
}

- (NSArray *)mf_allAppendersWithLevel
{
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");
    
    NSMutableArray *theAppendersWithLevel = [NSMutableArray new];
    
    for (SLLogAppenderNode *appenderNode in self.appenders) {
        [theAppendersWithLevel addObject:appenderNode->_appender];
    }
    
    return [theAppendersWithLevel copy];
}

- (void)mf_log:(SLLogMessage *)logMessage
{
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");
    
    if (_numProcessors > 1) {
        for (SLLogAppenderNode *appenderNode in self.appenders) {
            if (!(logMessage->_flag & appenderNode->_level)) {
                continue;
            }
            
            dispatch_group_async(_loggingGroup, appenderNode->_loggingQueue, ^{ @autoreleasepool {
                [appenderNode->_appender logMessage:logMessage];
            } });
        }
        
        dispatch_group_wait(_loggingGroup, DISPATCH_TIME_FOREVER);
    } else {
        for (SLLogAppenderNode *appenderNode in self.appenders) {
            if (!(logMessage->_flag & appenderNode->_level)) {
                continue;
            }
            
            dispatch_sync(appenderNode->_loggingQueue, ^{ @autoreleasepool {
                [appenderNode->_appender logMessage:logMessage];
            } });
        }
    }
    
    dispatch_semaphore_signal(_queueSemaphore);
}

- (void)mf_flushAppenders
{
    for (SLLogAppenderNode *appenderNode in self.appenders) {
        if ([appenderNode->_appender respondsToSelector:@selector(flush)]) {
            // dispatch_group_async(_loggingGroup, appenderNode->_loggingQueue, ^{ @autoreleasepool {
                [appenderNode->_appender flush];
            // } });
        }
    }
    
    dispatch_group_wait(_loggingGroup, DISPATCH_TIME_FOREVER);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

NSString * __nullable ATHExtractFileNameWithoutExtension(const char *filePath, BOOL copy)
{
    if (filePath == NULL) {
        return nil;
    }
    
    char *lastSlash = NULL;
    char *lastDot = NULL;
    
    char *p = (char *)filePath;
    
    while (*p != '\0') {
        if (*p == '/') {
            lastSlash = p;
        } else if (*p == '.') {
            lastDot = p;
        }
        
        p++;
    }
    
    char *subStr;
    NSUInteger subLen;
    
    if (lastSlash) {
        if (lastDot) {
            // lastSlash -> lastDot
            subStr = lastSlash + 1;
            subLen = (NSUInteger)(lastDot - subStr);
        } else {
            // lastSlash -> endOfString
            subStr = lastSlash + 1;
            subLen = (NSUInteger)(p - subStr);
        }
    } else {
        if (lastDot) {
            // startOfString -> lastDot
            subStr = (char *)filePath;
            subLen = (NSUInteger)(lastDot - subStr);
        } else {
            // startOfString -> endOfString
            subStr = (char *)filePath;
            subLen = (NSUInteger)(p - subStr);
        }
    }
    
    if (copy) {
        return [[NSString alloc] initWithBytes:subStr
                                        length:subLen
                                      encoding:NSUTF8StringEncoding];
    } else {
        // We can take advantage of the fact that __FILE__ is a string literal.
        // Specifically, we don't need to waste time copying the string.
        // We can just tell NSString to point to a range within the string literal.
        
        return [[NSString alloc] initWithBytesNoCopy:subStr
                                              length:subLen
                                            encoding:NSUTF8StringEncoding
                                        freeWhenDone:NO];
    }
}
@end
