//
//  SLDefaultLogFileManager.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLDefaultLogFileManager.h"
#import "SLLogger.h"
#import "SLLogFileInfo.h"

@interface SLDefaultLogFileManager () {
    NSUInteger _maximumNumberOfLogFiles;
    unsigned long long _logFilesDiskQuota;
    NSString *_logsDirectory;
}

- (void)deleteOldLogFiles;
- (NSString *)defaultLogsDirectory;

@end
@implementation SLDefaultLogFileManager
@synthesize maximumNumberOfLogFiles = _maximumNumberOfLogFiles;
@synthesize logFilesDiskQuota = _logFilesDiskQuota;

- (instancetype)init
{
    return [self initWithLogsDirectory:nil];
}

- (instancetype)initWithLogsDirectory:(NSString *)aLogsDirectory
{
    if ((self = [super init])  ) {
        _maximumNumberOfLogFiles = kSLDefaultLogMaxNumLogFiles;
        _logFilesDiskQuota = kSLDefaultLogFilesDiskQuota;
        
        if (aLogsDirectory) {
            _logsDirectory = [aLogsDirectory copy];
        } else {
            _logsDirectory = [[self defaultLogsDirectory] copy];
        }
        
        NSKeyValueObservingOptions kvoOptions = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
        
        [self addObserver:self forKeyPath:NSStringFromSelector(@selector(maximumNumberOfLogFiles)) options:kvoOptions context:nil];
        [self addObserver:self forKeyPath:NSStringFromSelector(@selector(logFilesDiskQuota)) options:kvoOptions context:nil];
        
        NSLog(@"ATHLogDefaultFileManager: logsDirectory:\n%@", [self logsDirectory]);
        NSLog(@"ATHLogDefaultFileManager: sortedLogFileNames:\n%@", [self sortedLogFileNames]);
    }
    
    return self;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)theKey
{
    BOOL automatic = NO;
    if ([theKey isEqualToString:@"maximumNumberOfLogFiles"] || [theKey isEqualToString:@"logFilesDiskQuota"]) {
        automatic = NO;
    } else {
        automatic = [super automaticallyNotifiesObserversForKey:theKey];
    }
    
    return automatic;
}

- (void)dealloc
{
    // try-catch because the observer might be removed or never added. In this case, removeObserver throws and exception
    @try {
        [self removeObserver:self forKeyPath:NSStringFromSelector(@selector(maximumNumberOfLogFiles))];
        [self removeObserver:self forKeyPath:NSStringFromSelector(@selector(logFilesDiskQuota))];
    } @catch (NSException *exception) {
    }
}

#pragma mark - Configuration

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    NSNumber *old = change[NSKeyValueChangeOldKey];
    NSNumber *new = change[NSKeyValueChangeNewKey];
    
    if ([old isEqual:new]) {
        // No change in value - don't bother with any processing.
        return;
    }
    
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(maximumNumberOfLogFiles))] ||
        [keyPath isEqualToString:NSStringFromSelector(@selector(logFilesDiskQuota))]) {
        NSLog(@"ATHLogDefaultFileManager: Responding to configuration change: %@", keyPath);
        
        dispatch_async([SLLogger globalLoggingQueue], ^{ @autoreleasepool {
            [self deleteOldLogFiles];
        } });
    }
}

#pragma mark - File Deleting

- (void)deleteOldLogFiles
{
    NSLog(@"ATHLogDefaultFileManager: deleteOldLogFiles");
    
    NSArray *sortedLogFileInfos = [self sortedLogFileInfos];
    
    NSUInteger firstIndexToDelete = NSNotFound;
    
    const unsigned long long diskQuota = self.logFilesDiskQuota;
    const NSUInteger maxNumLogFiles = self.maximumNumberOfLogFiles;
    
    if (diskQuota) {
        unsigned long long used = 0;
        
        for (NSUInteger i = 0; i < sortedLogFileInfos.count; i++) {
            SLLogFileInfo *info = sortedLogFileInfos[i];
            used += info.fileSize;
            
            if (used > diskQuota) {
                firstIndexToDelete = i;
                break;
            }
        }
    }
    
    if (maxNumLogFiles) {
        if (firstIndexToDelete == NSNotFound) {
            firstIndexToDelete = maxNumLogFiles;
        } else {
            firstIndexToDelete = MIN(firstIndexToDelete, maxNumLogFiles);
        }
    }
    
    if (firstIndexToDelete == 0) {
        // don't delete first file
        if (sortedLogFileInfos.count > 0) {
            SLLogFileInfo *logFileInfo = sortedLogFileInfos[0];
            
            if (!logFileInfo.isArchived) {
                // Don't delete active file.
                ++firstIndexToDelete;
            }
        }
    }
    
    if (firstIndexToDelete != NSNotFound) {
        // removing all logfiles starting with firstIndexToDelete
        for (NSUInteger i = firstIndexToDelete; i < sortedLogFileInfos.count; i++) {
            SLLogFileInfo *logFileInfo = sortedLogFileInfos[i];
            
            NSLog(@"ATHLogDefaultFileManager: Deleting file: %@", logFileInfo.fileName);
            
            [[NSFileManager defaultManager] removeItemAtPath:logFileInfo.filePath error:nil];
        }
    }
}

#pragma mark - Log Files

- (NSString *)defaultLogsDirectory
{
#if TARGET_OS_IPHONE
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *baseDir = paths.firstObject;
    NSString *logsDirectory = [baseDir stringByAppendingPathComponent:@"Logs"];
    
#else
    NSString *appName = [[NSProcessInfo processInfo] processName];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? paths[0] : NSTemporaryDirectory();
    NSString *logsDirectory = [[basePath stringByAppendingPathComponent:@"Logs"] stringByAppendingPathComponent:appName];
    
#endif
    
    return logsDirectory;
}

- (NSString *)logsDirectory
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:_logsDirectory]) {
        NSError *err = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:_logsDirectory
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&err]) {
            NSLog(@"ATHLogDefaultFileManager: Error creating logsDirectory: %@", err);
        }
    }
    
    return _logsDirectory;
}

- (BOOL)isLogFile:(NSString *)fileName
{
    NSString *appName = [self applicationName];
    
    BOOL hasProperPrefix = [fileName hasPrefix:[appName stringByAppendingString:@" "]];
    BOOL hasProperSuffix = [fileName hasSuffix:@".log"] || [fileName containsString:@".log."];
    
    return (hasProperPrefix && hasProperSuffix);
}

- (NSDateFormatter *)logFileDateFormatter
{
    NSMutableDictionary *dictionary = [[NSThread currentThread]
                                       threadDictionary];
    NSString *dateFormat = @"yyyy'-'MM'-'dd'--'HH'-'mm'-'ss'";
    NSString *key = [NSString stringWithFormat:@"logFileDateFormatter.%@", dateFormat];
    NSDateFormatter *dateFormatter = dictionary[key];
    
    if (dateFormatter == nil) {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Shanghai"]];
        [dateFormatter setDateFormat:dateFormat];
        dictionary[key] = dateFormatter;
    }
    
    return dateFormatter;
}

- (NSArray *)unsortedLogFilePaths
{
    NSString *logsDirectory = [self logsDirectory];
    NSArray *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:logsDirectory error:nil];
    
    NSMutableArray *unsortedLogFilePaths = [NSMutableArray arrayWithCapacity:[fileNames count]];
    
    for (NSString *fileName in fileNames) {
        // Filter out any files that aren't log files. (Just for extra safety)
        
#if TARGET_IPHONE_SIMULATOR
        // In case of iPhone simulator there can be 'archived' extension. isLogFile:
        // method knows nothing about it. Thus removing it for this method.
        //
        // See full explanation in the header file.
        NSString *theFileName = [fileName stringByReplacingOccurrencesOfString:@".archived"
                                                                    withString:@""];
        
        if ([self isLogFile:theFileName])
#else
            
            if ([self isLogFile:fileName])
#endif
            {
                NSString *filePath = [logsDirectory stringByAppendingPathComponent:fileName];
                
                [unsortedLogFilePaths addObject:filePath];
            }
    }
    
    return unsortedLogFilePaths;
}

- (NSArray *)unsortedLogFileNames
{
    NSArray *unsortedLogFilePaths = [self unsortedLogFilePaths];
    
    NSMutableArray *unsortedLogFileNames = [NSMutableArray arrayWithCapacity:[unsortedLogFilePaths count]];
    
    for (NSString *filePath in unsortedLogFilePaths) {
        [unsortedLogFileNames addObject:[filePath lastPathComponent]];
    }
    
    return unsortedLogFileNames;
}

- (NSArray *)unsortedLogFileInfos
{
    NSArray *unsortedLogFilePaths = [self unsortedLogFilePaths];
    
    NSMutableArray *unsortedLogFileInfos = [NSMutableArray arrayWithCapacity:[unsortedLogFilePaths count]];
    
    for (NSString *filePath in unsortedLogFilePaths) {
        SLLogFileInfo *logFileInfo = [[SLLogFileInfo alloc] initWithFilePath:filePath];
        
        [unsortedLogFileInfos addObject:logFileInfo];
    }
    
    return unsortedLogFileInfos;
}

- (NSArray *)sortedLogFilePaths
{
    NSArray *sortedLogFileInfos = [self sortedLogFileInfos];
    
    NSMutableArray *sortedLogFilePaths = [NSMutableArray arrayWithCapacity:[sortedLogFileInfos count]];
    
    for (SLLogFileInfo *logFileInfo in sortedLogFileInfos) {
        [sortedLogFilePaths addObject:[logFileInfo filePath]];
    }
    
    return sortedLogFilePaths;
}

- (NSArray *)sortedLogFileNames
{
    NSArray *sortedLogFileInfos = [self sortedLogFileInfos];
    
    NSMutableArray *sortedLogFileNames = [NSMutableArray arrayWithCapacity:[sortedLogFileInfos count]];
    
    for (SLLogFileInfo *logFileInfo in sortedLogFileInfos) {
        [sortedLogFileNames addObject:[logFileInfo fileName]];
    }
    
    return sortedLogFileNames;
}

- (NSArray *)sortedLogFileInfos
{
    return  [[self unsortedLogFileInfos] sortedArrayUsingComparator:^NSComparisonResult(SLLogFileInfo   * _Nonnull obj1, SLLogFileInfo   * _Nonnull obj2) {
        NSDate *date1 = [NSDate new];
        NSDate *date2 = [NSDate new];
        
        NSArray<NSString *> *arrayComponent = [[obj1 fileName] componentsSeparatedByString:@" "];
        if (arrayComponent.count > 0) {
            NSString *stringDate = arrayComponent.lastObject;
            stringDate = [stringDate stringByReplacingOccurrencesOfString:@".log" withString:@""];
            stringDate = [stringDate stringByReplacingOccurrencesOfString:@".archived" withString:@""];
            date1 = [[self logFileDateFormatter] dateFromString:stringDate] ?: [obj1 creationDate];
        }
        
        arrayComponent = [[obj2 fileName] componentsSeparatedByString:@" "];
        if (arrayComponent.count > 0) {
            NSString *stringDate = arrayComponent.lastObject;
            stringDate = [stringDate stringByReplacingOccurrencesOfString:@".log" withString:@""];
            stringDate = [stringDate stringByReplacingOccurrencesOfString:@".archived" withString:@""];
            date2 = [[self logFileDateFormatter] dateFromString:stringDate] ?: [obj2 creationDate];
        }
        
        return [date2 compare:date1 ?: [NSDate new]];
    }];
    
}

#pragma mark - Creation

- (NSString *)newLogFileName
{
    NSString *appName = [self applicationName];
    
    NSDateFormatter *dateFormatter = [self logFileDateFormatter];
    NSString *formattedDate = [dateFormatter stringFromDate:[NSDate date]];
    
    return [NSString stringWithFormat:@"%@ %@.log", appName, formattedDate];
}

- (NSString *)createNewLogFile {
    NSString *fileName = [self newLogFileName];
    NSString *logsDirectory = [self logsDirectory];
    
    NSUInteger attempt = 1;
    
    do {
        NSString *actualFileName = fileName;
        
        if (attempt > 1) {
            NSString *extension = [actualFileName pathExtension];
            
            actualFileName = [actualFileName stringByDeletingPathExtension];
            actualFileName = [actualFileName stringByAppendingFormat:@" %lu", (unsigned long)attempt];
            
            if (extension.length) {
                actualFileName = [actualFileName stringByAppendingPathExtension:extension];
            }
        }
        
        NSString *filePath = [logsDirectory stringByAppendingPathComponent:actualFileName];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            NSLog(@"DDLogFileManagerDefault: Creating new log file: %@", actualFileName);
            
            NSDictionary *attributes = nil;
            
#if TARGET_OS_IPHONE
            // When creating log file on iOS we're setting NSFileProtectionKey attribute to NSFileProtectionCompleteUnlessOpen.
            //
            // But in case if app is able to launch from background we need to have an ability to open log file any time we
            // want (even if device is locked). Thats why that attribute have to be changed to
            // NSFileProtectionCompleteUntilFirstUserAuthentication.
            
            NSFileProtectionType key = (sl_doesAppRunInBackground() ? NSFileProtectionCompleteUntilFirstUserAuthentication : NSFileProtectionCompleteUnlessOpen);
            
            attributes = @{
                           NSFileProtectionKey: key
                           };
#endif
            
            [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:attributes];
            
            [self deleteOldLogFiles];
            
            return filePath;
        } else {
            attempt++;
        }
    } while (YES);
}

#pragma mark -  Utility

- (NSString *)applicationName
{
    static NSString *_appName;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
        
        if (!_appName) {
            _appName = [[NSProcessInfo processInfo] processName];
        }
        
        if (!_appName) {
            _appName = @"";
        }
    });
    
    return _appName;
}


@end
