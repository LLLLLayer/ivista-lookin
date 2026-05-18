#import <Foundation/Foundation.h>

@class RACSignal;
@class LKCLIConnectedApp;

@interface LKCLIAppScanner : NSObject

- (RACSignal *)fetchAppsWithImages:(BOOL)needImages;
- (RACSignal *)fetchHierarchyForApp:(LKCLIConnectedApp *)app;
- (RACSignal *)fetchHierarchyDetailsWithTaskPackages:(NSArray *)packages forApp:(LKCLIConnectedApp *)app;
- (RACSignal *)fetchObjectWithOID:(unsigned long)oid forApp:(LKCLIConnectedApp *)app;
- (RACSignal *)fetchAttributeGroupsWithOID:(unsigned long)oid forApp:(LKCLIConnectedApp *)app;
- (void)closeAllConnections;

@end
