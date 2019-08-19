//
//  SLFunctionsWatcher.h
//  SmartLogger
//
//  Created by Li Hejun on 2019/8/19.
//  Copyright © 2019 Hejun. All rights reserved.
//

#import <Foundation/Foundation.h>

#if __cplusplus
extern "C" {
#endif
    // Enables/disables logging for the current thread.
    void WatcherSetup();
    void Watcher_enableLogging();
    void Watcher_disableLogging();
#if __cplusplus
}
#endif
NS_ASSUME_NONNULL_BEGIN

@interface SLFunctionsWatcher : NSObject

+ (instancetype)shared;
+ (void)watchClass:(Class)cls selector:(SEL)selector;

@end

NS_ASSUME_NONNULL_END
