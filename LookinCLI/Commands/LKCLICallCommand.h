#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLICallCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
