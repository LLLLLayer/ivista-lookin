#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIAppsCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
