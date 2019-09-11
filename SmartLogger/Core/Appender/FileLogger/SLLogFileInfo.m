//
//  SLLogFileInfo.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLLogFileInfo.h"
#import <sys/xattr.h>

#if TARGET_IPHONE_SIMULATOR
static NSString * const kSLXAttrArchivedName = @"archived";
#else
static NSString * const kSLXAttrArchivedName = @"smartlogger.log.archived";
#endif

@interface SLLogFileInfo () {
    __strong NSString *_filePath;
    __strong NSString *_fileName;
    
    __strong NSDictionary *_fileAttributes;
    
    __strong NSDate *_creationDate;
    __strong NSDate *_modificationDate;
    
    unsigned long long _fileSize;
}

@end

@implementation SLLogFileInfo
@synthesize filePath;

@dynamic fileName;
@dynamic fileAttributes;
@dynamic creationDate;
@dynamic modificationDate;
@dynamic fileSize;
@dynamic age;
@dynamic isArchived;

+ (instancetype)logFileWithPath:(NSString *)aFilePath
{
    return [[self alloc] initWithFilePath:aFilePath];
}

- (instancetype)initWithFilePath:(NSString *)aFilePath
{
    if ((self = [super init])) {
        filePath = [aFilePath copy];
    }
    
    return self;
}

#pragma mark - Getters

- (NSDictionary *)fileAttributes
{
    if (_fileAttributes == nil && filePath != nil) {
        _fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
    }
    
    return _fileAttributes;
}

- (NSString *)fileName
{
    if (_fileName == nil) {
        _fileName = [filePath lastPathComponent];
    }
    
    return _fileName;
}

- (NSDate *)modificationDate
{
    if (_modificationDate == nil) {
        _modificationDate = self.fileAttributes[NSFileModificationDate];
    }
    
    return _modificationDate;
}

- (NSDate *)creationDate
{
    if (_creationDate == nil) {
        _creationDate = self.fileAttributes[NSFileCreationDate];
    }
    
    return _creationDate;
}

- (unsigned long long)fileSize
{
    if (_fileSize == 0) {
        _fileSize = [self.fileAttributes[NSFileSize] unsignedLongLongValue];
    }
    
    return _fileSize;
}

- (NSTimeInterval)age
{
    return [[self creationDate] timeIntervalSinceNow] * -1.0;
}

- (NSString *)description
{
    return [@{ @"filePath": self.filePath ? : @"",
               @"fileName": self.fileName ? : @"",
               @"fileAttributes": self.fileAttributes ? : @"",
               @"creationDate": self.creationDate ? : @"",
               @"modificationDate": self.modificationDate ? : @"",
               @"fileSize": @(self.fileSize),
               @"age": @(self.age),
               @"isArchived": @(self.isArchived) } description];
}

#pragma mark - Archiving

- (BOOL)isArchived
{
#if TARGET_IPHONE_SIMULATOR
    
    return [self hasExtensionAttributeWithName:kSLXAttrArchivedName];
    
#else
    
    return [self hasExtendedAttributeWithName:kSLXAttrArchivedName];
    
#endif
}

- (void)setIsArchived:(BOOL)flag
{
#if TARGET_IPHONE_SIMULATOR
    
    if (flag) {
        [self addExtensionAttributeWithName:kSLXAttrArchivedName];
    } else {
        [self removeExtensionAttributeWithName:kSLXAttrArchivedName];
    }
    
#else
    
    if (flag) {
        [self addExtendedAttributeWithName:kSLXAttrArchivedName];
    } else {
        [self removeExtendedAttributeWithName:kSLXAttrArchivedName];
    }
    
#endif
}

#pragma mark - Changes

- (void)reset
{
    _fileName = nil;
    _fileAttributes = nil;
    _creationDate = nil;
    _modificationDate = nil;
}

- (void)renameFile:(NSString *)newFileName
{
    if (![newFileName isEqualToString:[self fileName]]) {
        NSString *fileDir = [filePath stringByDeletingLastPathComponent];
        
        NSString *newFilePath = [fileDir stringByAppendingPathComponent:newFileName];
        
        NSLog(@"DDLogFileInfo: Renaming file: '%@' -> '%@'", self.fileName, newFileName);
        
        NSError *error = nil;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:newFilePath] &&
            ![[NSFileManager defaultManager] removeItemAtPath:newFilePath error:&error]) {
            NSLog(@"DDLogFileInfo: Error deleting archive (%@): %@", self.fileName, error);
        }
        
        if (![[NSFileManager defaultManager] moveItemAtPath:filePath toPath:newFilePath error:&error]) {
            NSLog(@"DDLogFileInfo: Error renaming file (%@): %@", self.fileName, error);
        }
        
        filePath = newFilePath;
        [self reset];
    }
}

#pragma mark - Attribute Management

#if TARGET_IPHONE_SIMULATOR

- (BOOL)hasExtensionAttributeWithName:(NSString *)attrName
{
    
    NSArray *components = [[self fileName] componentsSeparatedByString:@"."];
    
    for (NSUInteger i = 1; i < components.count; i++) {
        NSString *attr = components[i];
        
        if ([attrName isEqualToString:attr]) {
            return YES;
        }
    }
    
    return NO;
}

- (void)addExtensionAttributeWithName:(NSString *)attrName
{
    
    if ([attrName length] == 0) {
        return;
    }
    
    // Example:
    // attrName = "archived"
    //
    // "mylog.txt" -> "mylog.archived.txt"
    // "mylog"     -> "mylog.archived"
    
    NSArray *components = [[self fileName] componentsSeparatedByString:@"."];
    
    NSUInteger count = [components count];
    
    NSUInteger estimatedNewLength = [[self fileName] length] + [attrName length] + 1;
    NSMutableString *newFileName = [NSMutableString stringWithCapacity:estimatedNewLength];
    
    if (count > 0) {
        [newFileName appendString:components.firstObject];
    }
    
    NSString *lastExt = @"";
    
    NSUInteger i;
    
    for (i = 1; i < count; i++) {
        NSString *attr = components[i];
        
        if ([attr length] == 0) {
            continue;
        }
        
        if ([attrName isEqualToString:attr]) {
            // Extension attribute already exists in file name
            return;
        }
        
        if ([lastExt length] > 0) {
            [newFileName appendFormat:@".%@", lastExt];
        }
        
        lastExt = attr;
    }
    
    [newFileName appendFormat:@".%@", attrName];
    
    if ([lastExt length] > 0) {
        [newFileName appendFormat:@".%@", lastExt];
    }
    
    [self renameFile:newFileName];
}

- (void)removeExtensionAttributeWithName:(NSString *)attrName
{
    
    if ([attrName length] == 0) {
        return;
    }
    
    // Example:
    // attrName = "archived"
    //
    // "mylog.archived.txt" -> "mylog.txt"
    // "mylog.archived"     -> "mylog"
    
    NSArray *components = [[self fileName] componentsSeparatedByString:@"."];
    
    NSUInteger count = [components count];
    
    NSUInteger estimatedNewLength = [[self fileName] length];
    NSMutableString *newFileName = [NSMutableString stringWithCapacity:estimatedNewLength];
    
    if (count > 0) {
        [newFileName appendString:components.firstObject];
    }
    
    BOOL found = NO;
    
    NSUInteger i;
    
    for (i = 1; i < count; i++) {
        NSString *attr = components[i];
        
        if ([attrName isEqualToString:attr]) {
            found = YES;
        } else {
            [newFileName appendFormat:@".%@", attr];
        }
    }
    
    if (found) {
        [self renameFile:newFileName];
    }
}

#else /* if TARGET_IPHONE_SIMULATOR */

- (BOOL)hasExtendedAttributeWithName:(NSString *)attrName
{
    const char *path = [filePath UTF8String];
    const char *name = [attrName UTF8String];
    
    ssize_t result = getxattr(path, name, NULL, 0, 0, 0);
    
    return (result >= 0);
}

- (void)addExtendedAttributeWithName:(NSString *)attrName
{
    const char *path = [filePath UTF8String];
    const char *name = [attrName UTF8String];
    
    int result = setxattr(path, name, NULL, 0, 0, 0);
    
    if (result < 0) {
        NSLog(@"ATHLogFileInfo: setxattr(%@, %@): error = %s",
              attrName,
              filePath,
              strerror(errno));
    }
}

- (void)removeExtendedAttributeWithName:(NSString *)attrName
{
    const char *path = [filePath UTF8String];
    const char *name = [attrName UTF8String];
    
    int result = removexattr(path, name, 0);
    
    if (result < 0 && errno != ENOATTR) {
        NSLog(@"ATHLogFileInfo: removexattr(%@, %@): error = %s",
              attrName,
              self.fileName,
              strerror(errno));
    }
}

#endif /* if TARGET_IPHONE_SIMULATOR */

#pragma mark - Comparisons

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[self class]]) {
        SLLogFileInfo *another = (SLLogFileInfo *)object;
        
        return [filePath isEqualToString:[another filePath]];
    }
    
    return NO;
}

-(NSUInteger)hash
{
    return [filePath hash];
}

- (NSComparisonResult)reverseCompareByCreationDate:(SLLogFileInfo *)another
{
    NSDate *us = [self creationDate];
    NSDate *them = [another creationDate];
    
    NSComparisonResult result = [us compare:them];
    
    if (result == NSOrderedAscending) {
        return NSOrderedDescending;
    }
    
    if (result == NSOrderedDescending) {
        return NSOrderedAscending;
    }
    
    return NSOrderedSame;
}

- (NSComparisonResult)reverseCompareByModificationDate:(SLLogFileInfo *)another
{
    NSDate *us = [self modificationDate];
    NSDate *them = [another modificationDate];
    
    NSComparisonResult result = [us compare:them];
    
    if (result == NSOrderedAscending) {
        return NSOrderedDescending;
    }
    
    if (result == NSOrderedDescending) {
        return NSOrderedAscending;
    }
    
    return NSOrderedSame;
}

@end
