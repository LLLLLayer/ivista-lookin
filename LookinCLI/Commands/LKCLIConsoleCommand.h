#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIConsoleCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
