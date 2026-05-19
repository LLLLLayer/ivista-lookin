#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLIAttrsCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;
+ (void)printTextWithResult:(id)result groupFilter:(NSString *)groupFilter;
+ (LKCLIExitCode)printJSONWithResult:(id)result groupFilter:(NSString *)groupFilter;

@end
