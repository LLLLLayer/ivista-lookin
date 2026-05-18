#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLISetCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
