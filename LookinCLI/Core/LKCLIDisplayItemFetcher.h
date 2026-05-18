#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@class LKCLIConnectedApp, LookinAttributesGroup, LookinDisplayItem, LookinHierarchyInfo, LookinObject;

@interface LKCLIDisplayItemFetchResult : NSObject

@property(nonatomic, strong) LKCLIConnectedApp *app;
@property(nonatomic, strong) LookinHierarchyInfo *hierarchyInfo;
@property(nonatomic, strong) LookinDisplayItem *displayItem;
@property(nonatomic, strong) LookinObject *object;
@property(nonatomic, copy) NSArray<LookinAttributesGroup *> *attributeGroups;
@property(nonatomic, assign) unsigned long requestedOID;
@property(nonatomic, assign) unsigned long detailOID;

@end

@interface LKCLIDisplayItemFetcher : NSObject

+ (BOOL)parseOIDValue:(NSString *)value oid:(unsigned long *)oid;
- (LKCLIExitCode)fetchBundleID:(NSString *)bundleID oid:(unsigned long)oid result:(LKCLIDisplayItemFetchResult **)result;

@end
