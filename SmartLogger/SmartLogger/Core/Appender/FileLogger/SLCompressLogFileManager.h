//
//  SLCompressLogFileManager.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLDefaultLogFileManager.h"
#import "SLInterfaces.h"

NS_ASSUME_NONNULL_BEGIN

@interface SLCompressLogFileManager : SLDefaultLogFileManager
/// compress block setted by App
@property (nonatomic, copy) SLLogArchiveCompressBlock compressBlock;
/// switch
@property (nonatomic, assign) BOOL on;
@end

NS_ASSUME_NONNULL_END
