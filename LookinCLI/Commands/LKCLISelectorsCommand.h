#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLISelectorsCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
