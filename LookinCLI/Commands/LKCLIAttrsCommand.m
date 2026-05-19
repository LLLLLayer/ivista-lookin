#import "LKCLIAttrsCommand.h"
#import "LKCLIAppSelector.h"
#import "LKCLIArgumentParser.h"
#import "LKCLIAttributeFormatter.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLIJSONWriter.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinDisplayItem.h"
#import "LookinObject.h"
#import <AppKit/AppKit.h>

@implementation LKCLIAttrsCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    NSString *groupFilter = nil;
    unsigned long oid = 0;
    BOOL json = NO;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
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
            NSString *oidValue = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&oidValue errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            if (![LKCLIDisplayItemFetcher parseOIDValue:oidValue oid:&oid]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--group"]) {
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&groupFilter errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'ivista-lookin attrs --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (oid == 0) {
        [LKCLIStdIO writeError:@"error: --oid is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin tree --bundle-id %@' to find object ids", selection.bundleID];
        return LKCLIExitCodeUsage;
    }

    LKCLIDisplayItemFetchResult *result = nil;
    LKCLIExitCode exitCode = [[LKCLIDisplayItemFetcher new] fetchSelection:selection oid:oid result:&result];
    if (exitCode != LKCLIExitCodeOK) {
        return exitCode;
    }

    if (json) {
        return [self printJSONWithResult:result groupFilter:groupFilter];
    }
    [self printTextWithResult:result groupFilter:groupFilter];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  ivista-lookin attrs --bundle-id <bundle-id> --oid <oid> [--group <filter>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Fetch dashboard attributes for a reachable iOS app object."];
}

+ (void)printTextWithResult:(LKCLIDisplayItemFetchResult *)result groupFilter:(NSString *)groupFilter {
    LKCLIConnectedApp *app = result.app;
    LookinObject *object = result.object;

    [LKCLIStdIO writeOut:@"%@ (%@)", app.appInfo.appName ?: @"<unknown>", app.appInfo.appBundleIdentifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"object:"];
    [LKCLIStdIO writeOut:@"  oid: %lu", object.oid];
    [LKCLIStdIO writeOut:@"  class: %@", object.rawClassName ?: @"<unknown>"];
    if (groupFilter.length) {
        [LKCLIStdIO writeOut:@"  group filter: %@", groupFilter];
    }
    [LKCLIStdIO writeOut:@"attributes:"];
    [LKCLIAttributeFormatter printGroups:result.attributeGroups groupFilter:groupFilter baseIndent:@"  "];
}

+ (LKCLIExitCode)printJSONWithResult:(LKCLIDisplayItemFetchResult *)result groupFilter:(NSString *)groupFilter {
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
        @"groupFilter": groupFilter ?: [NSNull null],
        @"attributes": [LKCLIAttributeFormatter JSONObjectsForGroups:result.attributeGroups groupFilter:groupFilter],
    };

    return [LKCLIJSONWriter printJSONObject:root];
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
