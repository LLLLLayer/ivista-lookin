#import "LKCLIAppsCommand.h"
#import "LKCLIAppScanner.h"
#import "LKCLIConnectedApp.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"

@implementation LKCLIAppsCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    BOOL json = NO;
    for (NSString *argument in arguments) {
        if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin apps --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    id value = nil;
    NSError *error = nil;
    BOOL succeeded = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:8 value:&value error:&error];
    [scanner closeAllConnections];

    if (!succeeded) {
        [LKCLIStdIO writeError:@"error: %@", error.localizedDescription ?: @"failed to fetch apps"];
        return LKCLIExitCodeConnection;
    }

    NSArray<LKCLIConnectedApp *> *apps = [value isKindOfClass:[NSArray class]] ? value : @[];
    if (json) {
        return [self printJSONWithApps:apps];
    }
    [self printTextWithApps:apps];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin apps [--json]\n"
      "\n"
      "List iOS apps that are currently reachable through LookinServer."];
}

+ (void)printTextWithApps:(NSArray<LKCLIConnectedApp *> *)apps {
    if (apps.count == 0) {
        [LKCLIStdIO writeOut:@"No inspectable apps found."];
        return;
    }

    for (NSUInteger idx = 0; idx < apps.count; idx++) {
        LKCLIConnectedApp *app = apps[idx];
        if (app.serverVersionError) {
            [LKCLIStdIO writeOut:@"%lu. version-error: %@", (unsigned long)(idx + 1), app.serverVersionError.localizedDescription ?: @"LookinServer version mismatch"];
            continue;
        }

        LookinAppInfo *info = app.appInfo;
        NSString *name = info.appName.length ? info.appName : @"<unknown>";
        NSString *bundleID = info.appBundleIdentifier.length ? info.appBundleIdentifier : @"<unknown>";
        NSString *device = info.deviceDescription.length ? info.deviceDescription : @"<unknown device>";
        NSString *os = info.osDescription.length ? info.osDescription : @"?";
        NSString *serverVersion = info.serverReadableVersion.length ? info.serverReadableVersion : [NSString stringWithFormat:@"%d", info.serverVersion];

        [LKCLIStdIO writeOut:@"%lu. %@ (%@)", (unsigned long)(idx + 1), name, bundleID];
        [LKCLIStdIO writeOut:@"   device: %@, iOS %@", device, os];
        [LKCLIStdIO writeOut:@"   transport: %@:%ld, server: %@", app.transport ?: @"unknown", (long)app.port, serverVersion];
    }
}

+ (LKCLIExitCode)printJSONWithApps:(NSArray<LKCLIConnectedApp *> *)apps {
    NSMutableArray<NSDictionary *> *objects = [NSMutableArray arrayWithCapacity:apps.count];
    for (LKCLIConnectedApp *app in apps) {
        NSMutableDictionary *object = [NSMutableDictionary dictionary];
        object[@"transport"] = app.transport ?: [NSNull null];
        object[@"port"] = @(app.port);
        if (app.deviceID) {
            object[@"deviceID"] = app.deviceID;
        }

        if (app.serverVersionError) {
            object[@"status"] = @"serverVersionError";
            object[@"error"] = app.serverVersionError.localizedDescription ?: @"LookinServer version mismatch";
            [objects addObject:object.copy];
            continue;
        }

        LookinAppInfo *info = app.appInfo;
        object[@"status"] = @"ok";
        object[@"name"] = info.appName ?: [NSNull null];
        object[@"bundleIdentifier"] = info.appBundleIdentifier ?: [NSNull null];
        object[@"device"] = info.deviceDescription ?: [NSNull null];
        object[@"os"] = info.osDescription ?: [NSNull null];
        object[@"deviceType"] = [self deviceTypeName:info.deviceType];
        object[@"screen"] = @{@"width": @(info.screenWidth), @"height": @(info.screenHeight), @"scale": @(info.screenScale)};
        object[@"serverVersion"] = @(info.serverVersion);
        object[@"serverReadableVersion"] = info.serverReadableVersion ?: [NSNull null];
        object[@"swiftEnabledInLookinServer"] = @(info.swiftEnabledInLookinServer);
        [objects addObject:object.copy];
    }

    NSError *error = nil;
    NSJSONWritingOptions options = objects.count ? (NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) : NSJSONWritingSortedKeys;
    NSData *data = [NSJSONSerialization dataWithJSONObject:objects options:options error:&error];
    if (!data) {
        [LKCLIStdIO writeError:@"error: %@", error.localizedDescription ?: @"failed to encode JSON"];
        return LKCLIExitCodeGeneralError;
    }
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [LKCLIStdIO writeOut:@"%@", jsonString];
    return LKCLIExitCodeOK;
}

+ (NSString *)deviceTypeName:(LookinAppInfoDevice)deviceType {
    switch (deviceType) {
        case LookinAppInfoDeviceSimulator:
            return @"simulator";
        case LookinAppInfoDeviceIPad:
            return @"ipad";
        case LookinAppInfoDeviceOthers:
            return @"iphone";
    }
}

@end
