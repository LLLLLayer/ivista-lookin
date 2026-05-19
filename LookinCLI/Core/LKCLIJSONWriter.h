#import "LKCLIExitCode.h"
#import <Foundation/Foundation.h>

@interface LKCLIJSONWriter : NSObject

+ (LKCLIExitCode)printJSONObject:(id)object;

@end
