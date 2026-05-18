#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

NS_ASSUME_NONNULL_BEGIN

@interface LKCLIHelpCommand : NSObject

+ (LKCLIExitCode)run;

@end

NS_ASSUME_NONNULL_END
