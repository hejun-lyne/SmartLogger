//
//  SLTTYLogAppender.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLTTYLogAppender.h"
#import "SLLogMessage.h"
#import "SLLogFormatter.h"

#import <unistd.h>
#import <sys/uio.h>

@interface SLTTYLogAppender () {
    NSString *_appName;
    char *_app;
    size_t _appLen;
    
    NSString *_processID;
    char *_pid;
    size_t _pidLen;
}
@end

@implementation SLTTYLogAppender
static BOOL ttyAppenderEnable;
+ (BOOL)enable
{
    return ttyAppenderEnable;
}

+ (void)setEnable:(BOOL)enable
{
    ttyAppenderEnable = enable;
}

- (instancetype)init
{
    
    if ((self = [super init])) {
        // Initialze 'app' variable (char *)
        
        _appName = [[NSProcessInfo processInfo] processName];
        _appLen = [_appName lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        
        if (_appLen == 0) {
            _appName = @"<UnnamedApp>";
            _appLen = [_appName lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        }
        
        _app = (char *)malloc(_appLen + 1);
        if (_app == NULL) {
            return nil;
        }
        
        BOOL processedAppName = [_appName getCString:_app maxLength:(_appLen + 1) encoding:NSUTF8StringEncoding];
        
        if (NO == processedAppName) {
            free(_app);
            return nil;
        }
        
        // Initialize 'pid' variable (char *)
        
        _processID = [NSString stringWithFormat:@"%i", (int)getpid()];
        
        _pidLen = [_processID lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        _pid = (char *)malloc(_pidLen + 1);
        
        if (_pid == NULL) {
            free(_app);
            return nil;
        }
        
        BOOL processedID = [_processID getCString:_pid maxLength:(_pidLen + 1) encoding:NSUTF8StringEncoding];
        
        if (NO == processedID) {
            free(_app);
            free(_pid);
            return nil;
        }
        
        _automaticallyAppendNewlineForCustomFormatters = YES;
    }
    
    return self;
}

- (void)logMessage:(SLLogMessage *)logMessage
{
    if (!self.class.enable) {
        return;
    }
    NSString *logMsg = logMessage->_message;
    BOOL isFormatted = NO;
    
    if (_logFormatter) {
        logMsg = [_logFormatter formatLogMessage:logMessage];
        isFormatted = logMsg != logMessage->_message;
    }
    
    if (logMsg) {
        // Convert log message to C string.
        //
        // We use the stack instead of the heap for speed if possible.
        // But we're extra cautious to avoid a stack overflow.
        
        NSUInteger msgLen = [logMsg lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        const BOOL useStack = msgLen < (1024 * 4);
        
        char msgStack[useStack ? (msgLen + 1) : 1]; // Analyzer doesn't like zero-size array, hence the 1
        char *msg = useStack ? msgStack : (char *)malloc(msgLen + 1);
        
        if (msg == NULL) {
            return;
        }
        
        BOOL logMsgEnc = [logMsg getCString:msg maxLength:(msgLen + 1) encoding:NSUTF8StringEncoding];
        
        if (!logMsgEnc) {
            if (!useStack && msg != NULL) {
                free(msg);
            }
            
            return;
        }
        
        // Write the log message to STDERR
        
        if (isFormatted) {
            // The log message has already been formatted.
            int iovec_len = (_automaticallyAppendNewlineForCustomFormatters) ? 5 : 4;
            struct iovec v[iovec_len];
            
            v[0].iov_base = "";
            v[0].iov_len = 0;
            
            v[1].iov_base = "";
            v[1].iov_len = 0;
            
            v[iovec_len - 1].iov_base = "";
            v[iovec_len - 1].iov_len = 0;
            
            v[2].iov_base = (char *)msg;
            v[2].iov_len = msgLen;
            
            if (iovec_len == 5) {
                v[3].iov_base = "\n";
                v[3].iov_len = (msg[msgLen] == '\n') ? 0 : 1;
            }
            
            writev(STDERR_FILENO, v, iovec_len);
        } else {
            // The log message is unformatted, so apply standard NSLog style formatting.
            
            int len;
            char ts[24] = "";
            size_t tsLen = 0;
            
            // Calculate timestamp.
            // The technique below is faster than using NSDateFormatter.
            if (logMessage->_timestamp) {
                NSTimeInterval epoch = [logMessage->_timestamp timeIntervalSince1970];
                struct tm tm;
                time_t time = (time_t)epoch;
                (void)localtime_r(&time, &tm);
                int milliseconds = (int)((epoch - floor(epoch)) * 1000.0);
                
                len = snprintf(ts, 24, "%04d-%02d-%02d %02d:%02d:%02d:%03d", // yyyy-MM-dd HH:mm:ss:SSS
                               tm.tm_year + 1900,
                               tm.tm_mon + 1,
                               tm.tm_mday,
                               tm.tm_hour,
                               tm.tm_min,
                               tm.tm_sec, milliseconds);
                
                tsLen = (NSUInteger)MAX(MIN(24 - 1, len), 0);
            }
            
            // Calculate thread ID
            //
            // How many characters do we need for the thread id?
            // logMessage->machThreadID is of type mach_port_t, which is an unsigned int.
            //
            // 1 hex char = 4 bits
            // 8 hex chars for 32 bit, plus ending '\0' = 9
            
            char tid[9];
            len = snprintf(tid, 9, "%s", [logMessage->_threadID cStringUsingEncoding:NSUTF8StringEncoding]);
            
            size_t tidLen = (NSUInteger)MAX(MIN(9 - 1, len), 0);
            
            // Here is our format: "%s %s[%i:%s] %s", timestamp, appName, processID, threadID, logMsg
            
            struct iovec v[13];
            
            v[0].iov_base = "";
            v[0].iov_len = 0;
            
            v[1].iov_base = "";
            v[1].iov_len = 0;
            
            v[12].iov_base = "";
            v[12].iov_len = 0;
            
            v[2].iov_base = ts;
            v[2].iov_len = tsLen;
            
            v[3].iov_base = " ";
            v[3].iov_len = 1;
            
            v[4].iov_base = _app;
            v[4].iov_len = _appLen;
            
            v[5].iov_base = "[";
            v[5].iov_len = 1;
            
            v[6].iov_base = _pid;
            v[6].iov_len = _pidLen;
            
            v[7].iov_base = ":";
            v[7].iov_len = 1;
            
            v[8].iov_base = tid;
            v[8].iov_len = MIN((size_t)8, tidLen); // snprintf doesn't return what you might think
            
            v[9].iov_base = "] ";
            v[9].iov_len = 2;
            
            v[10].iov_base = (char *)msg;
            v[10].iov_len = msgLen;
            
            v[11].iov_base = "\n";
            v[11].iov_len = (msg[msgLen] == '\n') ? 0 : 1;
            
            writev(STDERR_FILENO, v, 13);
        }
        
        if (!useStack) {
            free(msg);
        }
    }
}

- (NSString *)appenderName
{
    return [self loggerName];
}

- (NSString *)loggerName
{
    return @"com.yy.athlogger.ttyappender";
}

@end
