#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIScreenshotCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
