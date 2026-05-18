#import <Foundation/Foundation.h>

@class RACSignal;
@class LKCLIConnectedApp;

@interface LKCLIAppScanner : NSObject

- (RACSignal *)fetchAppsWithImages:(BOOL)needImages;
- (RACSignal *)fetchHierarchyForApp:(LKCLIConnectedApp *)app;
- (void)closeAllConnections;

@end
