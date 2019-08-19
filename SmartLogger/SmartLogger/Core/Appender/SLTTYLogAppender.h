//
//  SLTTYLogAppender.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLAbstractLogAppender.h"

NS_ASSUME_NONNULL_BEGIN

@interface SLTTYLogAppender : SLAbstractLogAppender
@property (class, assign) BOOL enable;
/**
 * Automatic append '\n'. Default value is YES.
 **/
@property(nonatomic, readwrite, assign) BOOL automaticallyAppendNewlineForCustomFormatters;

@end

NS_ASSUME_NONNULL_END
