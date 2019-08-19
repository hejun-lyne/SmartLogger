//
//  SLLogFileInfo.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SLLogFileInfo : NSObject
@property (strong, nonatomic, readonly) NSString *filePath;
@property (strong, nonatomic, readonly) NSString *fileName;

#if FOUNDATION_SWIFT_SDK_EPOCH_AT_LEAST(8)
@property (strong, nonatomic, readonly) NSDictionary<NSFileAttributeKey, id> *fileAttributes;
#else
@property (strong, nonatomic, readonly) NSDictionary<NSString *, id> *fileAttributes;
#endif

@property (strong, nonatomic, readonly) NSDate *creationDate;
@property (strong, nonatomic, readonly) NSDate *modificationDate;
@property (nonatomic, readonly) unsigned long long fileSize;
@property (nonatomic, readonly) NSTimeInterval age;
@property (nonatomic, readwrite) BOOL isArchived;

+ (instancetype)logFileWithPath:(NSString *)filePath;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFilePath:(NSString *)filePath NS_DESIGNATED_INITIALIZER;

- (void)reset;
- (void)renameFile:(NSString *)newFileName;

#if TARGET_IPHONE_SIMULATOR

// "mylog.txt" -> "mylog.archived.txt"
// "mylog"     -> "mylog.archived"
- (BOOL)hasExtensionAttributeWithName:(NSString *)attrName;
- (void)addExtensionAttributeWithName:(NSString *)attrName;
- (void)removeExtensionAttributeWithName:(NSString *)attrName;

#else /* if TARGET_IPHONE_SIMULATOR */

- (BOOL)hasExtendedAttributeWithName:(NSString *)attrName;
- (void)addExtendedAttributeWithName:(NSString *)attrName;
- (void)removeExtendedAttributeWithName:(NSString *)attrName;

#endif /* if TARGET_IPHONE_SIMULATOR */

- (NSComparisonResult)reverseCompareByCreationDate:(SLLogFileInfo *)another;
- (NSComparisonResult)reverseCompareByModificationDate:(SLLogFileInfo *)another;

@end

NS_ASSUME_NONNULL_END
