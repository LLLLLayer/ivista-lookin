#import "LKCLIConnectionRequest.h"

@implementation LKCLIConnectionRequest

- (void)resetTimeoutCount {
    [self endTimeoutCount];
    if (self.timeoutInterval > 0) {
        [self performSelector:@selector(_handleTimeout) withObject:nil afterDelay:self.timeoutInterval];
    }
}

- (void)endTimeoutCount {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)_handleTimeout {
    if (self.timeoutBlock) {
        self.timeoutBlock(self);
    }
}

@end
