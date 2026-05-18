#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIExportCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;

@end
