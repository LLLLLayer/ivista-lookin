#import "LKCLIInspectCommand.h"
#import "LKCLIAppSelector.h"
#import "LKCLIAttributeFormatter.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinDisplayItem.h"
#import "LookinObject.h"
#import <AppKit/AppKit.h>

@implementation LKCLIInspectCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    unsigned long oid = 0;
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
        } else if ([argument isEqualToString:@"--oid"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --oid requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *oidValue = arguments[++idx];
            if (![LKCLIDisplayItemFetcher parseOIDValue:oidValue oid:&oid]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin inspect --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (oid == 0) {
        [LKCLIStdIO writeError:@"error: --oid is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin tree --bundle-id %@' to find object ids", selection.bundleID];
        return LKCLIExitCodeUsage;
    }

    LKCLIDisplayItemFetchResult *result = nil;
    LKCLIExitCode exitCode = [[LKCLIDisplayItemFetcher new] fetchSelection:selection oid:oid result:&result];
    if (exitCode != LKCLIExitCodeOK) {
        return exitCode;
    }

    if (json) {
        return [self printJSONWithResult:result];
    }
    [self printTextWithResult:result];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin inspect --bundle-id <bundle-id> --oid <oid> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Fetch object metadata and dashboard attributes for a reachable iOS app."];
}

+ (void)printTextWithResult:(LKCLIDisplayItemFetchResult *)result {
    LKCLIConnectedApp *app = result.app;
    LookinDisplayItem *displayItem = result.displayItem;
    LookinObject *object = result.object;

    [LKCLIStdIO writeOut:@"%@ (%@)", app.appInfo.appName ?: @"<unknown>", app.appInfo.appBundleIdentifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"display item:"];
    [LKCLIStdIO writeOut:@"  view oid: %@", displayItem.viewObject ? [NSString stringWithFormat:@"%lu", displayItem.viewObject.oid] : @"nil"];
    [LKCLIStdIO writeOut:@"  layer oid: %@", displayItem.layerObject ? [NSString stringWithFormat:@"%lu", displayItem.layerObject.oid] : @"nil"];
    [LKCLIStdIO writeOut:@"  controller oid: %@", displayItem.hostViewControllerObject ? [NSString stringWithFormat:@"%lu", displayItem.hostViewControllerObject.oid] : @"nil"];
    [LKCLIStdIO writeOut:@"  frame: (%.3f, %.3f, %.3f, %.3f)", displayItem.frame.origin.x, displayItem.frame.origin.y, displayItem.frame.size.width, displayItem.frame.size.height];
    [LKCLIStdIO writeOut:@"  hidden: %@", displayItem.isHidden ? @"YES" : @"NO"];
    [LKCLIStdIO writeOut:@"  alpha: %.3f", displayItem.alpha];

    [LKCLIStdIO writeOut:@"object:"];
    [LKCLIStdIO writeOut:@"  oid: %lu", object.oid];
    [LKCLIStdIO writeOut:@"  class: %@", object.rawClassName ?: @"<unknown>"];
    if (object.memoryAddress.length) {
        [LKCLIStdIO writeOut:@"  memory: %@", object.memoryAddress];
    }
    if (object.classChainList.count) {
        [LKCLIStdIO writeOut:@"  class chain:"];
        for (NSString *className in object.classChainList) {
            [LKCLIStdIO writeOut:@"    - %@", className];
        }
    }
    if (object.specialTrace.length) {
        [LKCLIStdIO writeOut:@"  special trace: %@", object.specialTrace];
    }

    [LKCLIStdIO writeOut:@"attributes:"];
    [LKCLIAttributeFormatter printGroups:result.attributeGroups groupFilter:nil baseIndent:@"  "];
}

+ (LKCLIExitCode)printJSONWithResult:(LKCLIDisplayItemFetchResult *)result {
    LKCLIConnectedApp *app = result.app;
    LookinObject *object = result.object;
    NSDictionary *root = @{
        @"app": @{
            @"name": app.appInfo.appName ?: [NSNull null],
            @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
            @"device": app.appInfo.deviceDescription ?: [NSNull null],
            @"os": app.appInfo.osDescription ?: [NSNull null],
        },
        @"displayItem": [self JSONObjectForDisplayItem:result.displayItem],
        @"object": @{
            @"oid": @(object.oid),
            @"className": object.rawClassName ?: [NSNull null],
            @"memoryAddress": object.memoryAddress ?: [NSNull null],
            @"classChain": object.classChainList ?: @[],
            @"specialTrace": object.specialTrace ?: [NSNull null],
        },
        @"attributes": [LKCLIAttributeFormatter JSONObjectsForGroups:result.attributeGroups groupFilter:nil],
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

+ (NSDictionary *)JSONObjectForDisplayItem:(LookinDisplayItem *)displayItem {
    CGRect frame = displayItem.frame;
    return @{
        @"viewOid": displayItem.viewObject ? @(displayItem.viewObject.oid) : [NSNull null],
        @"layerOid": displayItem.layerObject ? @(displayItem.layerObject.oid) : [NSNull null],
        @"hostViewControllerOid": displayItem.hostViewControllerObject ? @(displayItem.hostViewControllerObject.oid) : [NSNull null],
        @"className": displayItem.displayingObject.rawClassName ?: [NSNull null],
        @"customTitle": displayItem.customDisplayTitle ?: [NSNull null],
        @"hidden": @(displayItem.isHidden),
        @"alpha": @(displayItem.alpha),
        @"keyWindow": @(displayItem.representedAsKeyWindow),
        @"frame": @{
            @"x": @(frame.origin.x),
            @"y": @(frame.origin.y),
            @"width": @(frame.size.width),
            @"height": @(frame.size.height),
        },
    };
}

@end
