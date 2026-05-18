#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIInspectCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
