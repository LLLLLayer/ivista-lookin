#import "LKCLITreeCommand.h"
#import "LKCLIAppScanner.h"
#import "LKCLIAppSelector.h"
#import "LKCLIConnectedApp.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinHierarchyInfo.h"
#import "LookinDisplayItem.h"
#import "LookinObject.h"

@implementation LKCLITreeCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    BOOL json = NO;
    NSInteger depth = NSIntegerMax;

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
        } else if ([argument isEqualToString:@"--depth"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --depth requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *depthValue = arguments[++idx];
            NSInteger parsedDepth = 0;
            if (![self parseDepthValue:depthValue depth:&parsedDepth]) {
                [LKCLIStdIO writeError:@"error: --depth must be a non-negative integer"];
                return LKCLIExitCodeUsage;
            }
            depth = parsedDepth;
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin tree --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }

    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    id appsValue = nil;
    NSError *appsError = nil;
    BOOL fetchedApps = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:8 value:&appsValue error:&appsError];
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
    [scanner closeAllConnections];

    if (!fetchedHierarchy) {
        [LKCLIStdIO writeError:@"error: %@", hierarchyError.localizedDescription ?: @"failed to fetch hierarchy"];
        return LKCLIExitCodeConnection;
    }
    if (![hierarchyValue isKindOfClass:[LookinHierarchyInfo class]]) {
        [LKCLIStdIO writeError:@"error: invalid hierarchy response"];
        return LKCLIExitCodeGeneralError;
    }

    LookinHierarchyInfo *hierarchyInfo = hierarchyValue;
    if (json) {
        return [self printJSONWithHierarchy:hierarchyInfo app:app depth:depth];
    }
    [self printTextWithHierarchy:hierarchyInfo app:app depth:depth];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin tree --bundle-id <bundle-id> [--json] [--depth N] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Fetch and print the UI hierarchy for a reachable iOS app."];
}

+ (BOOL)parseDepthValue:(NSString *)value depth:(NSInteger *)depth {
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

    NSString *maxValue = [NSString stringWithFormat:@"%ld", (long)NSIntegerMax];
    if (normalizedValue.length > maxValue.length ||
        (normalizedValue.length == maxValue.length && [normalizedValue compare:maxValue] == NSOrderedDescending)) {
        return NO;
    }
    if (depth) {
        *depth = value.integerValue;
    }
    return YES;
}

+ (void)printTextWithHierarchy:(LookinHierarchyInfo *)hierarchyInfo app:(LKCLIConnectedApp *)app depth:(NSInteger)depth {
    LookinAppInfo *info = app.appInfo;
    [LKCLIStdIO writeOut:@"%@ (%@)", info.appName ?: @"<unknown>", info.appBundleIdentifier ?: @"<unknown>"];

    for (LookinDisplayItem *item in hierarchyInfo.displayItems) {
        [self printTextItem:item level:0 depth:depth];
    }
}

+ (void)printTextItem:(LookinDisplayItem *)item level:(NSInteger)level depth:(NSInteger)depth {
    if (level > depth) {
        return;
    }

    NSMutableString *indent = [NSMutableString string];
    for (NSInteger idx = 0; idx < level; idx++) {
        [indent appendString:@"  "];
    }

    LookinObject *object = item.displayingObject;
    NSString *className = object.rawClassName ?: @"<unknown>";
    NSString *title = item.customDisplayTitle.length ? [NSString stringWithFormat:@" %@", item.customDisplayTitle] : @"";
    NSString *objectIDs = [self secondaryObjectIDsTextForItem:item primaryObject:object];
    CGRect frame = item.frame;
    NSString *flags = [self flagsForItem:item];

    [LKCLIStdIO writeOut:@"%@- %@%@ oid=%lu%@ frame=(%.1f, %.1f, %.1f, %.1f)%@",
     indent,
     className,
     title,
     object.oid,
     objectIDs,
     frame.origin.x,
     frame.origin.y,
     frame.size.width,
     frame.size.height,
     flags];

    if (level == depth) {
        return;
    }
    for (LookinDisplayItem *subitem in item.subitems) {
        [self printTextItem:subitem level:level + 1 depth:depth];
    }
}

+ (NSString *)secondaryObjectIDsTextForItem:(LookinDisplayItem *)item primaryObject:(LookinObject *)primaryObject {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    if (item.viewObject && item.viewObject != primaryObject) {
        [ids addObject:[NSString stringWithFormat:@"viewOid=%lu", item.viewObject.oid]];
    }
    if (item.layerObject && item.layerObject != primaryObject) {
        [ids addObject:[NSString stringWithFormat:@"layerOid=%lu", item.layerObject.oid]];
    }
    if (item.hostViewControllerObject && item.hostViewControllerObject != primaryObject) {
        [ids addObject:[NSString stringWithFormat:@"controllerOid=%lu", item.hostViewControllerObject.oid]];
    }
    if (ids.count == 0) {
        return @"";
    }
    return [NSString stringWithFormat:@" %@", [ids componentsJoinedByString:@" "]];
}

+ (NSString *)flagsForItem:(LookinDisplayItem *)item {
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    if (item.representedAsKeyWindow) {
        [flags addObject:@"keyWindow"];
    }
    if (item.isHidden) {
        [flags addObject:@"hidden"];
    }
    if (item.alpha < 1) {
        [flags addObject:[NSString stringWithFormat:@"alpha=%.2f", item.alpha]];
    }
    if (flags.count == 0) {
        return @"";
    }
    return [NSString stringWithFormat:@" [%@]", [flags componentsJoinedByString:@", "]];
}

+ (LKCLIExitCode)printJSONWithHierarchy:(LookinHierarchyInfo *)hierarchyInfo app:(LKCLIConnectedApp *)app depth:(NSInteger)depth {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithCapacity:hierarchyInfo.displayItems.count];
    for (LookinDisplayItem *item in hierarchyInfo.displayItems) {
        [items addObject:[self JSONObjectForItem:item level:0 depth:depth]];
    }

    NSDictionary *root = @{
        @"app": @{
            @"name": app.appInfo.appName ?: [NSNull null],
            @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
            @"device": app.appInfo.deviceDescription ?: [NSNull null],
            @"os": app.appInfo.osDescription ?: [NSNull null],
        },
        @"items": items,
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

+ (NSDictionary *)JSONObjectForItem:(LookinDisplayItem *)item level:(NSInteger)level depth:(NSInteger)depth {
    LookinObject *object = item.displayingObject;
    CGRect frame = item.frame;

    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    json[@"oid"] = @(object.oid);
    json[@"viewOid"] = item.viewObject ? @(item.viewObject.oid) : [NSNull null];
    json[@"layerOid"] = item.layerObject ? @(item.layerObject.oid) : [NSNull null];
    json[@"hostViewControllerOid"] = item.hostViewControllerObject ? @(item.hostViewControllerObject.oid) : [NSNull null];
    json[@"className"] = object.rawClassName ?: [NSNull null];
    json[@"customTitle"] = item.customDisplayTitle ?: [NSNull null];
    json[@"hidden"] = @(item.isHidden);
    json[@"alpha"] = @(item.alpha);
    json[@"keyWindow"] = @(item.representedAsKeyWindow);
    json[@"frame"] = @{
        @"x": @(frame.origin.x),
        @"y": @(frame.origin.y),
        @"width": @(frame.size.width),
        @"height": @(frame.size.height),
    };

    NSMutableArray<NSDictionary *> *children = [NSMutableArray array];
    if (level < depth) {
        for (LookinDisplayItem *subitem in item.subitems) {
            [children addObject:[self JSONObjectForItem:subitem level:level + 1 depth:depth]];
        }
    }
    json[@"children"] = children;
    return json.copy;
}

@end
