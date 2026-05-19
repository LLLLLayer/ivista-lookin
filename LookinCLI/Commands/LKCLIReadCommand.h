#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIReadCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
