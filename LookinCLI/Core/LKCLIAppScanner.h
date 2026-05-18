#import <Foundation/Foundation.h>

@class RACSignal;

@interface LKCLIAppScanner : NSObject

- (RACSignal *)fetchAppsWithImages:(BOOL)needImages;
- (void)closeAllConnections;

@end
