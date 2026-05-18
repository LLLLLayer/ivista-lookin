#import "LKCLIAttrsCommand.h"
#import "LKCLIAttributeFormatter.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinDisplayItem.h"
#import "LookinObject.h"
#import <AppKit/AppKit.h>

@implementation LKCLIAttrsCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    NSString *bundleID = nil;
    NSString *groupFilter = nil;
    unsigned long oid = 0;
    BOOL json = NO;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([argument isEqualToString:@"--bundle-id"] || [argument isEqualToString:@"-b"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: %@ requires a value", argument];
                return LKCLIExitCodeUsage;
            }
            bundleID = arguments[++idx];
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
        } else if ([argument isEqualToString:@"--group"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --group requires a value"];
                return LKCLIExitCodeUsage;
            }
            groupFilter = arguments[++idx];
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin attrs --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (oid == 0) {
        [LKCLIStdIO writeError:@"error: --oid is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin tree --bundle-id %@' to find object ids", bundleID];
        return LKCLIExitCodeUsage;
    }

    LKCLIDisplayItemFetchResult *result = nil;
    LKCLIExitCode exitCode = [[LKCLIDisplayItemFetcher new] fetchBundleID:bundleID oid:oid result:&result];
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
      "  lookin attrs --bundle-id <bundle-id> --oid <oid> [--group <filter>] [--json]\n"
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
