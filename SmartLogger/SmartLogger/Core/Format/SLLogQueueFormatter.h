//
//  SLLogQueueFormatter.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogFormatter.h"

NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSUInteger, SLLogQueueFormatterMode){
    /**
     *  Thread safe for multiple appenders
     */
    SLLogQueueFormatterModeShared = 0,
    /**
     *  For single appender
     */
    SLLogQueueFormatterModeAlone,
};

@interface SLLogQueueFormatter : NSObject<SLLogFormatter>
@property (assign, atomic) NSUInteger minQueueLength;
@property (assign, atomic) NSUInteger maxQueueLength;

- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithMode:(SLLogQueueFormatterMode)mode;

/**
 * eg. "com.apple.main-queue" --> "main".
 **/
- (void)setReplacementString:(NSString *)shortLabel forQueueLabel:(NSString *)longLabel;

@end

NS_ASSUME_NONNULL_END
