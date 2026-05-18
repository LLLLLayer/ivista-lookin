#import "LKCLIExportCommand.h"
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
#import "LookinHierarchyFile.h"
#import "LookinHierarchyInfo.h"
#import "LookinObject.h"
#import "LookinStaticAsyncUpdateTask.h"
#import <AppKit/AppKit.h>

@interface LKCLIExportCommand ()
@end

@implementation LKCLIExportCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    NSString *outPath = nil;
    CGFloat compression = 1;
    BOOL json = NO;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([LKCLIAppSelector isSelectionArgument:argument]) {
            NSString *errorMessage = nil;
            if (![LKCLIAppSelector consumeSelectionArgument:argument arguments:arguments index:&idx selection:selection errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage ?: @"error: invalid app selector option"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--out"] || [argument isEqualToString:@"-o"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: %@ requires a value", argument];
                return LKCLIExitCodeUsage;
            }
            outPath = arguments[++idx];
        } else if ([argument isEqualToString:@"--compression"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --compression requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *compressionValue = arguments[++idx];
            if (![self parseCompressionValue:compressionValue compression:&compression]) {
                [LKCLIStdIO writeError:@"error: --compression must be a number between 0.01 and 1"];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin export --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (outPath.length == 0) {
        [LKCLIStdIO writeError:@"error: --out is required"];
        return LKCLIExitCodeUsage;
    }

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
    NSArray<LookinDisplayItem *> *flatItems = [LookinDisplayItem flatItemsFromHierarchicalItems:hierarchyInfo.displayItems];
    NSArray *packages = [self detailPackagesForItems:flatItems];
    id detailsValue = nil;
    NSError *detailsError = nil;
    BOOL fetchedDetails = [LKCLISignalRunner waitForSignal:[scanner fetchHierarchyDetailsWithTaskPackages:packages forApp:app] timeout:60 value:&detailsValue error:&detailsError];
    [scanner closeAllConnections];

    if (!fetchedDetails) {
        [LKCLIStdIO writeError:@"error: %@", detailsError.localizedDescription ?: @"failed to fetch hierarchy details"];
        return LKCLIExitCodeConnection;
    }

    NSUInteger appliedDetails = [self applyDetailsValue:detailsValue toItems:flatItems];
    NSError *archiveError = nil;
    NSData *exportData = [self exportDataFromHierarchyInfo:hierarchyInfo compression:compression error:&archiveError];
    if (!exportData) {
        [LKCLIStdIO writeError:@"error: %@", archiveError.localizedDescription ?: @"failed to encode lookin file"];
        return LKCLIExitCodeGeneralError;
    }

    NSString *finalPath = [self absolutePathForPath:outPath];
    NSError *writeError = nil;
    BOOL wrote = [exportData writeToFile:finalPath options:NSDataWritingAtomic error:&writeError];
    if (!wrote) {
        [LKCLIStdIO writeError:@"error: %@", writeError.localizedDescription ?: @"failed to write lookin file"];
        return LKCLIExitCodeGeneralError;
    }

    if (json) {
        return [self printJSONWithApp:app path:finalPath bytes:exportData.length itemCount:flatItems.count detailCount:appliedDetails compression:compression];
    }

    [LKCLIStdIO writeOut:@"exported %@ items to %@ (%lu bytes)", @(flatItems.count), finalPath, (unsigned long)exportData.length];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin export --bundle-id <bundle-id> --out <file.lookin> [--compression <0.01-1>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Export a .lookin snapshot containing hierarchy, attributes, and screenshots."];
}

+ (BOOL)parseCompressionValue:(NSString *)value compression:(CGFloat *)compression {
    if (value.length == 0) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    double parsedValue = 0;
    if (![scanner scanDouble:&parsedValue] || !scanner.isAtEnd) {
        return NO;
    }
    if (parsedValue < 0.01 || parsedValue > 1) {
        return NO;
    }
    if (compression) {
        *compression = parsedValue;
    }
    return YES;
}

+ (NSArray *)detailPackagesForItems:(NSArray<LookinDisplayItem *> *)items {
    NSMutableArray<LookinStaticAsyncUpdateTask *> *tasks = [NSMutableArray array];
    for (LookinDisplayItem *item in items) {
        if (item.customInfo || item.layerObject.oid == 0) {
            continue;
        }
        if (item.doNotFetchScreenshotReason == LookinFetchScreenshotPermitted) {
            [tasks addObject:[self taskForItem:item type:LookinStaticAsyncUpdateTaskTypeGroupScreenshot attrRequest:LookinDetailUpdateTaskAttrRequest_Need]];
            if (item.isExpandable) {
                [tasks addObject:[self taskForItem:item type:LookinStaticAsyncUpdateTaskTypeSoloScreenshot attrRequest:LookinDetailUpdateTaskAttrRequest_NotNeed]];
            }
        } else {
            [tasks addObject:[self taskForItem:item type:LookinStaticAsyncUpdateTaskTypeNoScreenshot attrRequest:LookinDetailUpdateTaskAttrRequest_Need]];
        }
    }
    return [self packagesFromTasks:tasks];
}

+ (LookinStaticAsyncUpdateTask *)taskForItem:(LookinDisplayItem *)item
                                        type:(LookinStaticAsyncUpdateTaskType)type
                                 attrRequest:(LookinDetailUpdateTaskAttrRequest)attrRequest {
    LookinStaticAsyncUpdateTask *task = [LookinStaticAsyncUpdateTask new];
    task.oid = item.layerObject.oid;
    task.frameSize = item.frame.size;
    task.taskType = type;
    task.attrRequest = attrRequest;
    task.needBasisVisualInfo = YES;
    task.clientReadableVersion = [LKCLIVersionProvider cliVersion];
    return task;
}

+ (NSArray *)packagesFromTasks:(NSArray<LookinStaticAsyncUpdateTask *> *)tasks {
    NSMutableArray<LookinStaticAsyncUpdateTasksPackage *> *packages = [NSMutableArray array];
    NSMutableArray<LookinStaticAsyncUpdateTask *> *bufferTasks = [NSMutableArray array];
    NSUInteger packageTotalArea = 0;
    NSUInteger packageMaxArea = 2000000;
    NSUInteger packageMaxTasksCount = 100;

    for (LookinStaticAsyncUpdateTask *task in tasks) {
        CGFloat currentArea = task.frameSize.width * task.frameSize.height;
        if ((packageTotalArea + currentArea > packageMaxArea) || bufferTasks.count >= packageMaxTasksCount) {
            if (bufferTasks.count > 0) {
                LookinStaticAsyncUpdateTasksPackage *package = [LookinStaticAsyncUpdateTasksPackage new];
                package.tasks = bufferTasks.copy;
                [packages addObject:package];
                [bufferTasks removeAllObjects];
                packageTotalArea = 0;
            }
        }

        packageTotalArea += currentArea;
        [bufferTasks addObject:task];
    }

    if (bufferTasks.count > 0) {
        LookinStaticAsyncUpdateTasksPackage *package = [LookinStaticAsyncUpdateTasksPackage new];
        package.tasks = bufferTasks.copy;
        [packages addObject:package];
    }
    return packages.copy;
}

+ (NSUInteger)applyDetailsValue:(id)detailsValue toItems:(NSArray<LookinDisplayItem *> *)items {
    if (![detailsValue isKindOfClass:[NSArray class]]) {
        return 0;
    }

    NSMutableDictionary<NSNumber *, LookinDisplayItem *> *itemsByLayerOID = [NSMutableDictionary dictionary];
    for (LookinDisplayItem *item in items) {
        if (item.layerObject.oid != 0) {
            itemsByLayerOID[@(item.layerObject.oid)] = item;
        }
    }

    NSUInteger count = 0;
    for (LookinDisplayItemDetail *detail in (NSArray *)detailsValue) {
        if (![detail isKindOfClass:[LookinDisplayItemDetail class]] || detail.failureCode == -1) {
            continue;
        }
        LookinDisplayItem *item = itemsByLayerOID[@(detail.displayItemOid)];
        if (!item) {
            continue;
        }
        [self applyDetail:detail toItem:item];
        count++;
    }
    return count;
}

+ (void)applyDetail:(LookinDisplayItemDetail *)detail toItem:(LookinDisplayItem *)item {
    if (detail.customDisplayTitle) {
        item.customDisplayTitle = detail.customDisplayTitle;
    }
    if (detail.danceUISource) {
        item.danceuiSource = detail.danceUISource;
    }
    if (detail.groupScreenshot) {
        item.groupScreenshot = detail.groupScreenshot;
    }
    if (detail.soloScreenshot) {
        item.soloScreenshot = detail.soloScreenshot;
    }
    if (detail.frameValue) {
        item.frame = detail.frameValue.rectValue;
    }
    if (detail.boundsValue) {
        item.bounds = detail.boundsValue.rectValue;
    }
    if (detail.hiddenValue) {
        item.isHidden = detail.hiddenValue.boolValue;
    }
    if (detail.alphaValue) {
        item.alpha = detail.alphaValue.floatValue;
    }
    if (detail.attributesGroupList) {
        item.attributesGroupList = detail.attributesGroupList;
    }
    if (detail.customAttrGroupList) {
        item.customAttrGroupList = detail.customAttrGroupList;
    }
}

+ (NSData *)exportDataFromHierarchyInfo:(LookinHierarchyInfo *)info compression:(CGFloat)compression error:(NSError **)error {
    LookinHierarchyFile *file = [LookinHierarchyFile new];
    file.serverVersion = info.serverVersion;
    file.hierarchyInfo = info;

    NSMutableDictionary<NSNumber *, NSData *> *soloScreenshots = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSData *> *groupScreenshots = [NSMutableDictionary dictionary];

    NSArray<LookinDisplayItem *> *allItems = [LookinDisplayItem flatItemsFromHierarchicalItems:info.displayItems];
    for (LookinDisplayItem *displayItem in allItems) {
        displayItem.screenshotEncodeType = LookinDisplayItemImageEncodeTypeNone;
        NSNumber *key = @(displayItem.layerObject.oid);
        NSData *soloData = [self compressedDataFromImage:displayItem.soloScreenshot compression:compression];
        NSData *groupData = [self compressedDataFromImage:displayItem.groupScreenshot compression:compression];
        if (soloData) {
            soloScreenshots[key] = soloData;
        }
        if (groupData) {
            groupScreenshots[key] = groupData;
        }
    }
    file.soloScreenshots = soloScreenshots.copy;
    file.groupScreenshots = groupScreenshots.copy;

    return [NSKeyedArchiver archivedDataWithRootObject:file requiringSecureCoding:YES error:error];
}

+ (NSData *)compressedDataFromImage:(NSImage *)sourceImage compression:(CGFloat)compression {
    if (!sourceImage) {
        return nil;
    }

    compression = MAX(MIN(compression, 1), 0.01);
    NSSize targetSize = NSMakeSize(sourceImage.size.width * compression, sourceImage.size.height * compression);
    NSRect targetFrame = NSMakeRect(0, 0, targetSize.width, targetSize.height);
    NSImageRep *sourceImageRep = [sourceImage bestRepresentationForRect:targetFrame context:nil hints:nil];
    if (!sourceImageRep) {
        return nil;
    }

    NSImage *resizedImage = [[NSImage alloc] initWithSize:targetSize];
    [resizedImage lockFocus];
    [sourceImageRep drawInRect:targetFrame];
    [resizedImage unlockFocus];

    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithData:resizedImage.TIFFRepresentation];
    return [imageRep TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1];
}

+ (NSString *)absolutePathForPath:(NSString *)path {
    NSString *expandedPath = [path stringByExpandingTildeInPath];
    if (expandedPath.isAbsolutePath) {
        return expandedPath;
    }
    return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:expandedPath];
}

+ (LKCLIExitCode)printJSONWithApp:(LKCLIConnectedApp *)app
                              path:(NSString *)path
                             bytes:(NSUInteger)bytes
                         itemCount:(NSUInteger)itemCount
                       detailCount:(NSUInteger)detailCount
                       compression:(CGFloat)compression {
    NSDictionary *root = @{
        @"app": @{
            @"name": app.appInfo.appName ?: [NSNull null],
            @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
            @"device": app.appInfo.deviceDescription ?: [NSNull null],
            @"os": app.appInfo.osDescription ?: [NSNull null],
        },
        @"path": path,
        @"bytes": @(bytes),
        @"itemCount": @(itemCount),
        @"detailCount": @(detailCount),
        @"compression": @(compression),
    };

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data) {
        [LKCLIStdIO writeError:@"error: %@", error.localizedDescription ?: @"failed to encode JSON"];
        return LKCLIExitCodeGeneralError;
    }
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [LKCLIStdIO writeOut:@"%@", jsonString];
    return LKCLIExitCodeOK;
}

@end
