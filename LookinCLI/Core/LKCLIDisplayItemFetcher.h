#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"
#import "LookinStaticAsyncUpdateTask.h"

@class LKCLIAppSelection, LKCLIConnectedApp, LookinAttributesGroup, LookinDisplayItem, LookinDisplayItemDetail, LookinHierarchyInfo, LookinObject;

@interface LKCLIDisplayItemFetchResult : NSObject

@property(nonatomic, strong) LKCLIConnectedApp *app;
@property(nonatomic, strong) LookinHierarchyInfo *hierarchyInfo;
@property(nonatomic, strong) LookinDisplayItem *displayItem;
@property(nonatomic, strong) LookinObject *object;
@property(nonatomic, strong) LookinDisplayItemDetail *detail;
@property(nonatomic, copy) NSArray<LookinAttributesGroup *> *attributeGroups;
@property(nonatomic, assign) unsigned long requestedOID;
@property(nonatomic, assign) unsigned long detailOID;

@end

@interface LKCLIDisplayItemFetcher : NSObject

+ (BOOL)parseOIDValue:(NSString *)value oid:(unsigned long *)oid;
- (LKCLIExitCode)fetchBundleID:(NSString *)bundleID oid:(unsigned long)oid result:(LKCLIDisplayItemFetchResult **)result;
- (LKCLIExitCode)fetchSelection:(LKCLIAppSelection *)selection oid:(unsigned long)oid result:(LKCLIDisplayItemFetchResult **)result;
- (LKCLIExitCode)fetchBundleID:(NSString *)bundleID
                            oid:(unsigned long)oid
                       taskType:(LookinStaticAsyncUpdateTaskType)taskType
                    attrRequest:(LookinDetailUpdateTaskAttrRequest)attrRequest
             needBasisVisualInfo:(BOOL)needBasisVisualInfo
                         result:(LKCLIDisplayItemFetchResult **)result;
- (LKCLIExitCode)fetchSelection:(LKCLIAppSelection *)selection
                             oid:(unsigned long)oid
                        taskType:(LookinStaticAsyncUpdateTaskType)taskType
                     attrRequest:(LookinDetailUpdateTaskAttrRequest)attrRequest
              needBasisVisualInfo:(BOOL)needBasisVisualInfo
                          result:(LKCLIDisplayItemFetchResult **)result;

@end
