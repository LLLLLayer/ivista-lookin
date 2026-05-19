#import <Foundation/Foundation.h>

@interface LKCLILookinAppGuard : NSObject

+ (BOOL)isLookinAppRunning;
+ (NSString *)runningAppSummary;
+ (void)warnIfLookinAppRunning;

@end
