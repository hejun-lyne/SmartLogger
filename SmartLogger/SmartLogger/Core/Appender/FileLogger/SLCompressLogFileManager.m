//
//  SLCompressLogFileManager.m
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/16.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import "SLCompressLogFileManager.h"
#import "SLLogFileInfo.h"
#import "SLLogger.h"

#import <zlib.h>

@interface SLLogFileInfo (Compress)
@property (nonatomic, readonly) BOOL isCompressed;

- (NSString *)tempFilePathByAppendingPathExtension:(NSString *)newExt;
- (NSString *)fileNameByAppendingPathExtension:(NSString *)newExt;

@end
@implementation SLCompressLogFileManager
{
    BOOL mUpToDate;
    BOOL mIsCompressing;
}

- (instancetype)init
{
    return [self initWithLogsDirectory:nil];
}

- (instancetype)initWithLogsDirectory:(NSString *)logsDirectory
{
    if ((self = [super initWithLogsDirectory:logsDirectory]))
    {
        mUpToDate = NO;
        _on = YES;
        [self performSelector:@selector(compressNext) withObject:nil afterDelay:5.0];
    }
    return self;
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(compressNext) object:nil];
}

- (void)didArchiveLogFile:(NSString *)logFilePath
{
    NSLog(@"ATHLogCompressFileManager: didArchiveLogFile: %@", [logFilePath lastPathComponent]);
    if (!self.on) {
        return;
    }
    if (mUpToDate) {
        [self compressLogFile:[SLLogFileInfo logFileWithPath:logFilePath]];
    }
}

- (void)didRollAndArchiveLogFile:(NSString *)logFilePath
{
    NSLog(@"ATHLogCompressFileManager: didRollAndArchiveLogFile: %@", [logFilePath lastPathComponent]);
    if (!self.on) {
        return;
    }
    if (mUpToDate) {
        [self compressLogFile:[SLLogFileInfo logFileWithPath:logFilePath]];
    }
}


- (void)compressLogFile:(SLLogFileInfo *)logFile
{
    mIsCompressing = YES;
    
    __weak __typeof(self)weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [weakSelf compressInBackground:logFile];
    });
}

- (void)compressNext
{
    if (!self.on) {
        return;
    }
    
    if (mIsCompressing)
    {
        return;
    }
    
    NSLog(@"ATHLogCompressFileManager: compressNextLogFile");
    mUpToDate = NO;
    NSArray *sortedLogFileInfos = [self sortedLogFileInfos];
    NSUInteger count = [sortedLogFileInfos count];
    if (count == 0) {
        // Nothing to compress
        mUpToDate = YES;
        return;
    }
    
    NSUInteger i = count;
    while (i > 0) {
        SLLogFileInfo *logFileInfo = [sortedLogFileInfos objectAtIndex:(i - 1)];
        if (logFileInfo.isArchived && !logFileInfo.isCompressed) {
            [self compressLogFile:logFileInfo];
            break;
        }
        i--;
    }
    
    mUpToDate = YES;
}

- (void)compressionDidSucceed:(SLLogFileInfo *)logFile
{
    NSLog(@"ATHLogCompressFileManager: compressionDidSucceed: %@", logFile.fileName);
    mIsCompressing = NO;
    [self compressNext];
}

- (void)compressionDidFail:(SLLogFileInfo *)logFile
{
    NSLog(@"ATHLogCompressFileManager: compressionDidFail: %@", logFile.fileName);
    mIsCompressing = NO;
    
    NSTimeInterval delay = (60 * 15); // 15 minutes
    [self performSelector:@selector(compressNext) withObject:nil afterDelay:delay];
}

- (void)compressInBackground:(SLLogFileInfo *)logFile
{
    if (!self.on) {
        return;
    }
    
    @autoreleasepool {
        
        void(^onSuccess)(NSString *) = ^(NSString *tempPath){
            SLLogFileInfo *compressedLogFile = [SLLogFileInfo logFileWithPath:tempPath];
            compressedLogFile.isArchived = YES;
            
            NSString *outputFileName = [logFile fileNameByAppendingPathExtension:@"gz"];
            [compressedLogFile renameFile:outputFileName];
            
            // Report success to class via logging thread/queue
            dispatch_async([SLLogger globalLoggingQueue], ^{ @autoreleasepool {
                [self compressionDidSucceed:compressedLogFile];
            }});
        };
        
        if (self.compressBlock != nil) {
            NSString *resultFile = self.compressBlock(logFile.filePath);
            if (resultFile != nil) {
                NSString *fileName = [resultFile lastPathComponent];
                NSString *matchFilePath = [[self logsDirectory] stringByAppendingPathComponent:fileName];
                if (![matchFilePath isEqualToString:resultFile]) {
                    NSError *error;
                    if ([[NSFileManager defaultManager] fileExistsAtPath:matchFilePath]) {
                        [[NSFileManager defaultManager] removeItemAtPath:matchFilePath error:&error];
                        if (error != nil) {
                            NSLog(@"CompressLogFile: remove file failed: %@", error);
                        }
                    }
                    [[NSFileManager defaultManager] moveItemAtPath:resultFile toPath:matchFilePath error:&error];
                    if (error != nil) {
                        NSLog(@"CompressLogFile: move file failed: %@", error);
                    }
                }
                NSError *error;
                BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:logFile.filePath error:&error];
                if (!ok) {
                    NSLog(@"Warning: failed to remove original file %@ after compression: %@", logFile.filePath, error);
                }
                onSuccess(matchFilePath);
                return;
            }
        }
        
        // Steps:
        //  1. Create a new file with the same fileName, but added "gzip" extension
        //  2. Open the new file for writing (output file)
        //  3. Open the given file for reading (input file)
        //  4. Setup zlib for gzip compression
        //  5. Read a chunk of the given file
        //  6. Compress the chunk
        //  7. Write the compressed chunk to the output file
        //  8. Repeat steps 5 - 7 until the input file is exhausted
        //  9. Close input and output file
        // 10. Teardown zlib
        
        
        // STEP 1
        
        NSString *inputFilePath = logFile.filePath;
        
        NSString *tempOutputFilePath = [logFile tempFilePathByAppendingPathExtension:@"gz"];
        
#if TARGET_OS_IPHONE
        // We use the same protection as the original file.  This means that it has the same security characteristics.
        // Also, if the app can run in the background, this means that it gets
        // NSFileProtectionCompleteUntilFirstUserAuthentication so that we can do this compression even with the
        // device locked.  c.f. DDFileLogger.doesAppRunInBackground.
        NSString* protection = logFile.fileAttributes[NSFileProtectionKey];
        NSDictionary* attributes = protection == nil ? nil : @{NSFileProtectionKey: protection};
        [[NSFileManager defaultManager] createFileAtPath:tempOutputFilePath contents:nil attributes:attributes];
#endif
        
        // STEP 2 & 3
        
        NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:inputFilePath];
        NSOutputStream *outputStream = [NSOutputStream outputStreamToFileAtPath:tempOutputFilePath append:NO];
        
        [inputStream open];
        [outputStream open];
        
        // STEP 4
        
        z_stream strm;
        
        // Zero out the structure before (to be safe) before we start using it
        bzero(&strm, sizeof(strm));
        
        strm.zalloc = Z_NULL;
        strm.zfree = Z_NULL;
        strm.opaque = Z_NULL;
        strm.total_out = 0;
        
        // Compresssion Levels:
        //   Z_NO_COMPRESSION
        //   Z_BEST_SPEED
        //   Z_BEST_COMPRESSION
        //   Z_DEFAULT_COMPRESSION
        
        deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (15+16), 8, Z_DEFAULT_STRATEGY);
        
        // Prepare our variables for steps 5-7
        //
        // inputDataLength  : Total length of buffer that we will read file data into
        // outputDataLength : Total length of buffer that zlib will output compressed bytes into
        //
        // Note: The output buffer can be smaller than the input buffer because the
        //       compressed/output data is smaller than the file/input data (obviously).
        //
        // inputDataSize : The number of bytes in the input buffer that have valid data to be compressed.
        //
        // Imagine compressing a tiny file that is actually smaller than our inputDataLength.
        // In this case only a portion of the input buffer would have valid file data.
        // The inputDataSize helps represent the portion of the buffer that is valid.
        //
        // Imagine compressing a huge file, but consider what happens when we get to the very end of the file.
        // The last read will likely only fill a portion of the input buffer.
        // The inputDataSize helps represent the portion of the buffer that is valid.
        
        NSUInteger inputDataLength  = (1024 * 2);  // 2 KB
        NSUInteger outputDataLength = (1024 * 1);  // 1 KB
        
        NSMutableData *inputData = [NSMutableData dataWithLength:inputDataLength];
        NSMutableData *outputData = [NSMutableData dataWithLength:outputDataLength];
        
        NSUInteger inputDataSize = 0;
        
        BOOL done = YES;
        NSError* error = nil;
        do
        {
            @autoreleasepool {
                
                // STEP 5
                // Read data from the input stream into our input buffer.
                //
                // inputBuffer : pointer to where we want the input stream to copy bytes into
                // inputBufferLength : max number of bytes the input stream should read
                //
                // Recall that inputDataSize is the number of valid bytes that already exist in the
                // input buffer that still need to be compressed.
                // This value is usually zero, but may be larger if a previous iteration of the loop
                // was unable to compress all the bytes in the input buffer.
                //
                // For example, imagine that we ready 2K worth of data from the file in the last loop iteration,
                // but when we asked zlib to compress it all, zlib was only able to compress 1.5K of it.
                // We would still have 0.5K leftover that still needs to be compressed.
                // We want to make sure not to skip this important data.
                //
                // The [inputData mutableBytes] gives us a pointer to the beginning of the underlying buffer.
                // When we add inputDataSize we get to the proper offset within the buffer
                // at which our input stream can start copying bytes into without overwriting anything it shouldn't.
                
                const void *inputBuffer = [inputData mutableBytes] + inputDataSize;
                NSUInteger inputBufferLength = inputDataLength - inputDataSize;
                
                NSInteger readLength = [inputStream read:(uint8_t *)inputBuffer maxLength:inputBufferLength];
                if (readLength < 0) {
                    error = [inputStream streamError];
                    break;
                }
                
                inputDataSize += readLength;
                
                // STEP 6
                // Ask zlib to compress our input buffer.
                // Tell it to put the compressed bytes into our output buffer.
                
                strm.next_in = (Bytef *)[inputData mutableBytes];   // Read from input buffer
                strm.avail_in = (uInt)inputDataSize;                // as much as was read from file (plus leftovers).
                
                strm.next_out = (Bytef *)[outputData mutableBytes]; // Write data to output buffer
                strm.avail_out = (uInt)outputDataLength;            // as much space as is available in the buffer.
                
                // When we tell zlib to compress our data,
                // it won't directly tell us how much data was processed.
                // Instead it keeps a running total of the number of bytes it has processed.
                // In other words, every iteration from the loop it increments its total values.
                // So to figure out how much data was processed in this iteration,
                // we fetch the totals before we ask it to compress data,
                // and then afterwards we subtract from the new totals.
                
                NSInteger prevTotalIn = strm.total_in;
                NSInteger prevTotalOut = strm.total_out;
                
                int flush = [inputStream hasBytesAvailable] ? Z_SYNC_FLUSH : Z_FINISH;
                deflate(&strm, flush);
                
                NSInteger inputProcessed = strm.total_in - prevTotalIn;
                NSInteger outputProcessed = strm.total_out - prevTotalOut;
                
                // STEP 7
                // Now write all compressed bytes to our output stream.
                //
                // It is theoretically possible that the write operation doesn't write everything we ask it to.
                // Although this is highly unlikely, we take precautions.
                // Also, we watch out for any errors (maybe the disk is full).
                
                NSUInteger totalWriteLength = 0;
                NSInteger writeLength = 0;
                
                do
                {
                    const void *outputBuffer = [outputData mutableBytes] + totalWriteLength;
                    NSUInteger outputBufferLength = outputProcessed - totalWriteLength;
                    
                    writeLength = [outputStream write:(const uint8_t *)outputBuffer maxLength:outputBufferLength];
                    
                    if (writeLength < 0)
                    {
                        error = [outputStream streamError];
                    }
                    else
                    {
                        totalWriteLength += writeLength;
                    }
                    
                } while((totalWriteLength < outputProcessed) && !error);
                
                // STEP 7.5
                //
                // We now have data in our input buffer that has already been compressed.
                // We want to remove all the processed data from the input buffer,
                // and we want to move any unprocessed data to the beginning of the buffer.
                //
                // If the amount processed is less than the valid buffer size, we have leftovers.
                
                NSUInteger inputRemaining = inputDataSize - inputProcessed;
                if (inputRemaining > 0)
                {
                    void *inputDst = [inputData mutableBytes];
                    void *inputSrc = [inputData mutableBytes] + inputProcessed;
                    
                    memmove(inputDst, inputSrc, inputRemaining);
                }
                
                inputDataSize = inputRemaining;
                
                // Are we done yet?
                
                done = ((flush == Z_FINISH) && (inputDataSize == 0));
                
                // STEP 8
                // Loop repeats until end of data (or unlikely error)
                
            } // end @autoreleasepool
            
        } while (!done && error == nil);
        
        // STEP 9
        
        [inputStream close];
        [outputStream close];
        
        // STEP 10
        
        deflateEnd(&strm);
        
        // We're done!
        // Report success or failure back to the logging thread/queue.
        
        if (error)
        {
            // Remove output file.
            // Our compression attempt failed.
            
            NSLog(@"Compression of %@ failed: %@", inputFilePath, error);
            error = nil;
            BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:tempOutputFilePath error:&error];
            if (!ok)
                NSLog(@"Failed to clean up %@ after failed compression: %@", tempOutputFilePath, error);
            
            // Report failure to class via logging thread/queue
            dispatch_async([SLLogger globalLoggingQueue], ^{ @autoreleasepool {
                [self compressionDidFail:logFile];
            }});
        }
        else
        {
            // Remove original input file.
            // It will be replaced with the new compressed version.
            
            error = nil;
            BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:inputFilePath error:&error];
            if (!ok)
                NSLog(@"Warning: failed to remove original file %@ after compression: %@", inputFilePath, error);
            
            // Mark the compressed file as archived,
            // and then move it into its final destination.
            //
            // temp-log-ABC123.txt.gz -> log-ABC123.txt.gz
            //
            // The reason we were using the "temp-" prefix was so the file would not be
            // considered a log file while it was only partially complete.
            // Only files that begin with "log-" are considered log files.
            
            onSuccess(tempOutputFilePath);
        }
        
    } // end @autoreleasepool
}

@end

@implementation SLLogFileInfo (Compress)
@dynamic isCompressed;

- (BOOL)isCompressed
{
    return [[[self fileName] pathExtension] isEqualToString:@"gz"];
}

- (NSString *)tempFilePathByAppendingPathExtension:(NSString *)newExt
{
    NSString *tempFileName = [NSString stringWithFormat:@"temp-%@", [self fileName]];
    NSString *newFileName = [tempFileName stringByAppendingPathExtension:newExt];
    NSString *fileDir = [[self filePath] stringByDeletingLastPathComponent];
    NSString *newFilePath = [fileDir stringByAppendingPathComponent:newFileName];
    
    return newFilePath;
}

- (NSString *)fileNameByAppendingPathExtension:(NSString *)newExt
{
    NSString *fileNameExtension = [[self fileName] pathExtension];
    if ([fileNameExtension isEqualToString:newExt]) {
        return [self fileName];
    }
    
    return [[self fileName] stringByAppendingPathExtension:newExt];
}

@end
