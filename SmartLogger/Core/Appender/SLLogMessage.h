//
//  SLLogMessage.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLInterfaces.h"

NS_ASSUME_NONNULL_BEGIN

@interface SLLogMessage : NSObject <NSCopying>
{
@public
    NSString *_message;
    SLLogLevel _level;
    SLLogFlag _flag;
    NSString *_file;
    NSString *_fileName;
    NSString *_function;
    NSUInteger _line;
    NSString *_tag;
    NSDate *_timestamp;
    NSString *_threadID;
    NSString *_threadName;
    NSString *_queueLabel;
    BOOL _noFormatter;
}

- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 * Recommend init method
 */
- (instancetype)initWithMessage:(NSString *)message
                          level:(SLLogLevel)level
                           flag:(SLLogFlag)flag
                           file:(NSString *)file
                       function:(NSString * __nullable)function
                           line:(NSUInteger)line
                            tag:(NSString * __nullable)tag
                      timestamp:(NSDate * __nullable)timestamp NS_DESIGNATED_INITIALIZER;

/**
 * Brief init method
 */
- (instancetype)initWithMessage:(NSString *)message
                            tag:(NSString * __nullable)tag NS_DESIGNATED_INITIALIZER;

/**
 *  The log message
 */
@property (readonly, nonatomic) NSString *message;
@property (readonly, nonatomic) SLLogLevel level;
@property (readonly, nonatomic) SLLogFlag flag;
@property (readonly, nonatomic) NSString *file;
@property (readonly, nonatomic) NSString *fileName;
@property (readonly, nonatomic) NSString * __nullable function;
@property (readonly, nonatomic) NSUInteger line;
@property (readonly, nonatomic) NSString * __nullable tag;
@property (readonly, nonatomic) NSDate *timestamp;
@property (readonly, nonatomic) NSString *threadID; // ID as it appears in NSLog calculated from the machThreadID
@property (readonly, nonatomic) NSString *threadName;
@property (readonly, nonatomic) NSString *queueLabel;
@property (readonly, nonatomic) BOOL noFormatter;

@end

NS_ASSUME_NONNULL_END
