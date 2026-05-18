#import <Foundation/Foundation.h>

@class RACSignal;

@interface LKCLISignalRunner : NSObject

+ (BOOL)waitForSignal:(RACSignal *)signal timeout:(NSTimeInterval)timeout value:(id *)value error:(NSError **)error;

@end
