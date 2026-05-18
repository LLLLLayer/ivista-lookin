#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLITreeCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
