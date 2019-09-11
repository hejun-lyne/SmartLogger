//
//  SLDefaultLogFileManager.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogFileManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface SLDefaultLogFileManager : NSObject<SLLogFileManager>
/*
 * Methods to override.
 *
 * File name format: `"<bundle identifier> <date> <time>.log"`
 * Example: `com.organization.myapp 2013-12-03 17-14.log`
 *
 **/
@property (readonly, copy) NSString *nextLogFileName;

- (instancetype)initWithLogsDirectory:(nullable NSString *)logsDirectory NS_DESIGNATED_INITIALIZER;
- (BOOL)isLogFile:(NSString *)fileName;

@end

NS_ASSUME_NONNULL_END
