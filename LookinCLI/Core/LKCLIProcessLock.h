#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIProcessLock : NSObject

+ (LKCLIExitCode)runDeviceCommandWithBlock:(LKCLIExitCode (^)(void))block;

@end
