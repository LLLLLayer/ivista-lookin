#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIAttrsCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
