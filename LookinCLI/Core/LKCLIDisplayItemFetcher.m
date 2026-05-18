#import "LKCLIDisplayItemFetcher.h"
#import "LKCLIAppScanner.h"
#import "LKCLIAppSelector.h"
#import "LKCLIConnectedApp.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LKCLIVersionProvider.h"
#import "LookinAppInfo.h"
#import "LookinAttributesGroup.h"
#import "LookinDisplayItem.h"
#import "LookinDisplayItemDetail.h"
#import "LookinHierarchyInfo.h"
#import "LookinObject.h"
#import "LookinStaticAsyncUpdateTask.h"
#import <limits.h>
#import <stdlib.h>

@implementation LKCLIDisplayItemFetchResult
@end

@implementation LKCLIDisplayItemFetcher

+ (BOOL)parseOIDValue:(NSString *)value oid:(unsigned long *)oid {
    if (value.length == 0) {
        return NO;
    }

    NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    NSCharacterSet *nonDigits = [digits invertedSet];
    if ([value rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return NO;
    }

    NSString *normalizedValue = value;
    while (normalizedValue.length > 1 && [normalizedValue hasPrefix:@"0"]) {
        normalizedValue = [normalizedValue substringFromIndex:1];
    }
    if ([normalizedValue isEqualToString:@"0"]) {
        return NO;
    }

    NSString *maxValue = [NSString stringWithFormat:@"%lu", ULONG_MAX];
    if (normalizedValue.length > maxValue.length ||
        (normalizedValue.length == maxValue.length && [normalizedValue compare:maxValue] == NSOrderedDescending)) {
        return NO;
    }
    if (oid) {
        *oid = strtoul(value.UTF8String, NULL, 10);
    }
    return YES;
}

- (LKCLIExitCode)fetchBundleID:(NSString *)bundleID oid:(unsigned long)oid result:(LKCLIDisplayItemFetchResult **)result {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    selection.bundleID = bundleID;
    return [self fetchSelection:selection oid:oid result:result];
}

- (LKCLIExitCode)fetchSelection:(LKCLIAppSelection *)selection oid:(unsigned long)oid result:(LKCLIDisplayItemFetchResult **)result {
    return [self fetchSelection:selection
                            oid:oid
                       taskType:LookinStaticAsyncUpdateTaskTypeNoScreenshot
                    attrRequest:LookinDetailUpdateTaskAttrRequest_Need
             needBasisVisualInfo:YES
                         result:result];
}

- (LKCLIExitCode)fetchBundleID:(NSString *)bundleID
                            oid:(unsigned long)oid
                       taskType:(LookinStaticAsyncUpdateTaskType)taskType
                    attrRequest:(LookinDetailUpdateTaskAttrRequest)attrRequest
             needBasisVisualInfo:(BOOL)needBasisVisualInfo
                         result:(LKCLIDisplayItemFetchResult **)result {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    selection.bundleID = bundleID;
    return [self fetchSelection:selection
                            oid:oid
                       taskType:taskType
                    attrRequest:attrRequest
             needBasisVisualInfo:needBasisVisualInfo
                         result:result];
}

- (LKCLIExitCode)fetchSelection:(LKCLIAppSelection *)selection
                             oid:(unsigned long)oid
                        taskType:(LookinStaticAsyncUpdateTaskType)taskType
                     attrRequest:(LookinDetailUpdateTaskAttrRequest)attrRequest
              needBasisVisualInfo:(BOOL)needBasisVisualInfo
                          result:(LKCLIDisplayItemFetchResult **)result {
    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    id appsValue = nil;
    NSError *appsError = nil;
    BOOL fetchedApps = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:10 value:&appsValue error:&appsError];
    if (!fetchedApps) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: %@", appsError.localizedDescription ?: @"failed to fetch apps"];
        return LKCLIExitCodeConnection;
    }

    LKCLIExitCode selectionExitCode = LKCLIExitCodeOK;
    LKCLIConnectedApp *app = [[LKCLIAppSelector new] selectAppFromAppsValue:appsValue selection:selection exitCode:&selectionExitCode];
    if (!app) {
        [scanner closeAllConnections];
        return selectionExitCode;
    }

    id hierarchyValue = nil;
    NSError *hierarchyError = nil;
    BOOL fetchedHierarchy = [LKCLISignalRunner waitForSignal:[scanner fetchHierarchyForApp:app] timeout:12 value:&hierarchyValue error:&hierarchyError];
    if (!fetchedHierarchy) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: %@", hierarchyError.localizedDescription ?: @"failed to fetch hierarchy"];
        return LKCLIExitCodeConnection;
    }
    if (![hierarchyValue isKindOfClass:[LookinHierarchyInfo class]]) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: invalid hierarchy response"];
        return LKCLIExitCodeGeneralError;
    }

    LookinHierarchyInfo *hierarchyInfo = hierarchyValue;
    LookinDisplayItem *displayItem = [self displayItemMatchingOID:oid inItems:hierarchyInfo.displayItems];
    if (!displayItem) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: no display item found for oid %lu", oid];
        return LKCLIExitCodeObjectNotFound;
    }

    LookinObject *object = [self preferredObjectForDisplayItem:displayItem requestedOID:oid];
    unsigned long detailOID = displayItem.layerObject.oid ?: object.oid;
    if (detailOID == 0) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: display item has no inspectable object for oid %lu", oid];
        return LKCLIExitCodeObjectNotFound;
    }

    NSArray *packages = [self detailPackagesForDisplayItem:displayItem
                                                  detailOID:detailOID
                                                   taskType:taskType
                                                attrRequest:attrRequest
                                         needBasisVisualInfo:needBasisVisualInfo];
    id detailsValue = nil;
    NSError *detailsError = nil;
    BOOL fetchedDetails = [LKCLISignalRunner waitForSignal:[scanner fetchHierarchyDetailsWithTaskPackages:packages forApp:app] timeout:12 value:&detailsValue error:&detailsError];
    [scanner closeAllConnections];

    if (!fetchedDetails) {
        [LKCLIStdIO writeError:@"error: %@", detailsError.localizedDescription ?: @"failed to fetch display item details"];
        return LKCLIExitCodeConnection;
    }

    LookinDisplayItemDetail *detail = [self detailFromDetailsValue:detailsValue detailOID:detailOID];
    LKCLIDisplayItemFetchResult *fetchResult = [LKCLIDisplayItemFetchResult new];
    fetchResult.app = app;
    fetchResult.hierarchyInfo = hierarchyInfo;
    fetchResult.displayItem = displayItem;
    fetchResult.object = object;
    fetchResult.detail = detail;
    fetchResult.attributeGroups = [self attributeGroupsFromDetail:detail fallbackItem:displayItem];
    fetchResult.requestedOID = oid;
    fetchResult.detailOID = detailOID;
    if (result) {
        *result = fetchResult;
    }
    return LKCLIExitCodeOK;
}

- (LookinDisplayItem *)displayItemMatchingOID:(unsigned long)oid inItems:(NSArray<LookinDisplayItem *> *)items {
    for (LookinDisplayItem *item in items) {
        if (item.viewObject.oid == oid || item.layerObject.oid == oid || item.hostViewControllerObject.oid == oid) {
            return item;
        }
        LookinDisplayItem *matchedSubitem = [self displayItemMatchingOID:oid inItems:item.subitems];
        if (matchedSubitem) {
            return matchedSubitem;
        }
    }
    return nil;
}

- (LookinObject *)preferredObjectForDisplayItem:(LookinDisplayItem *)item requestedOID:(unsigned long)oid {
    if (item.viewObject.oid == oid) {
        return item.viewObject;
    }
    if (item.layerObject.oid == oid) {
        return item.layerObject;
    }
    if (item.hostViewControllerObject.oid == oid) {
        return item.hostViewControllerObject;
    }
    return item.displayingObject ?: item.layerObject ?: item.hostViewControllerObject;
}

- (NSArray *)detailPackagesForDisplayItem:(LookinDisplayItem *)item
                                  detailOID:(unsigned long)detailOID
                                   taskType:(LookinStaticAsyncUpdateTaskType)taskType
                                attrRequest:(LookinDetailUpdateTaskAttrRequest)attrRequest
                         needBasisVisualInfo:(BOOL)needBasisVisualInfo {
    LookinStaticAsyncUpdateTask *task = [LookinStaticAsyncUpdateTask new];
    task.oid = detailOID;
    task.taskType = taskType;
    task.attrRequest = attrRequest;
    task.needBasisVisualInfo = needBasisVisualInfo;
    task.frameSize = item.frame.size;
    task.clientReadableVersion = [LKCLIVersionProvider cliVersion];

    LookinStaticAsyncUpdateTasksPackage *package = [LookinStaticAsyncUpdateTasksPackage new];
    package.tasks = @[task];
    return @[package];
}

- (LookinDisplayItemDetail *)detailFromDetailsValue:(id)detailsValue detailOID:(unsigned long)detailOID {
    if (![detailsValue isKindOfClass:[NSArray class]]) {
        return nil;
    }

    for (LookinDisplayItemDetail *detail in (NSArray *)detailsValue) {
        if (![detail isKindOfClass:[LookinDisplayItemDetail class]] || detail.failureCode == -1) {
            continue;
        }
        if (detail.displayItemOid != 0 && detail.displayItemOid != detailOID) {
            continue;
        }
        return detail;
    }
    return nil;
}

- (NSArray<LookinAttributesGroup *> *)attributeGroupsFromDetail:(LookinDisplayItemDetail *)detail fallbackItem:(LookinDisplayItem *)fallbackItem {
    NSMutableArray<LookinAttributesGroup *> *groups = [NSMutableArray array];
    if (detail) {
        [groups addObjectsFromArray:detail.attributesGroupList ?: @[]];
        [groups addObjectsFromArray:detail.customAttrGroupList ?: @[]];
        if (groups.count > 0) {
            return groups.copy;
        }
    }

    [groups addObjectsFromArray:fallbackItem.attributesGroupList ?: @[]];
    [groups addObjectsFromArray:fallbackItem.customAttrGroupList ?: @[]];
    return groups.copy;
}

@end
