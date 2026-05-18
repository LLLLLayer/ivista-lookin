#import <Foundation/Foundation.h>

@class RACSignal;
@class LKCLIConnectedApp;
@class LookinAttributeModification;
@class LookinCustomAttrModification;

@interface LKCLIAppScanner : NSObject

- (RACSignal *)fetchAppsWithImages:(BOOL)needImages;
- (RACSignal *)fetchHierarchyForApp:(LKCLIConnectedApp *)app;
- (RACSignal *)fetchHierarchyDetailsWithTaskPackages:(NSArray *)packages forApp:(LKCLIConnectedApp *)app;
- (RACSignal *)fetchObjectWithOID:(unsigned long)oid forApp:(LKCLIConnectedApp *)app;
- (RACSignal *)fetchAttributeGroupsWithOID:(unsigned long)oid forApp:(LKCLIConnectedApp *)app;
- (RACSignal *)fetchSelectorNamesWithClass:(NSString *)className hasArg:(BOOL)hasArg forApp:(LKCLIConnectedApp *)app;
- (RACSignal *)invokeMethodWithOID:(unsigned long)oid selectorName:(NSString *)selectorName forApp:(LKCLIConnectedApp *)app;
- (RACSignal *)submitInbuiltModification:(LookinAttributeModification *)modification forApp:(LKCLIConnectedApp *)app;
- (RACSignal *)submitCustomModification:(LookinCustomAttrModification *)modification forApp:(LKCLIConnectedApp *)app;
- (void)closeAllConnections;

@end
