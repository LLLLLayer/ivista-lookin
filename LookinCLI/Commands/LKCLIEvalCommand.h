#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIEvalCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
