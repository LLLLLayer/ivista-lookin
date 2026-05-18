#import "LKCLISignalRunner.h"
#import "LookinDefines.h"

@implementation LKCLISignalRunner

+ (BOOL)waitForSignal:(RACSignal *)signal timeout:(NSTimeInterval)timeout value:(id *)value error:(NSError **)error {
    __block BOOL finished = NO;
    __block id receivedValue = nil;
    __block NSError *receivedError = nil;

    RACDisposable *disposable = [signal subscribeNext:^(id x) {
        receivedValue = x;
    } error:^(NSError *subscriptionError) {
        receivedError = subscriptionError;
        finished = YES;
    } completed:^{
        finished = YES;
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!finished && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }

    if (!finished) {
        [disposable dispose];
        receivedError = [NSError errorWithDomain:LookinErrorDomain
                                            code:LookinErrCode_Timeout
                                        userInfo:@{NSLocalizedDescriptionKey: @"Operation timed out"}];
    }

    if (value) {
        *value = receivedValue;
    }
    if (error) {
        *error = receivedError;
    }
    return (receivedError == nil);
}

@end
