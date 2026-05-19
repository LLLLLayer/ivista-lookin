#import "LKCLIAppSelector.h"
#import "LKCLIArgumentParser.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"

@interface LKCLIAppSelector ()

+ (BOOL)app:(LKCLIConnectedApp *)app matchesSelection:(LKCLIAppSelection *)selection;
- (NSString *)selectionDescription:(LKCLIAppSelection *)selection;

@end

@implementation LKCLIAppSelection
@end

@implementation LKCLIAppSelector

+ (BOOL)isSelectionArgument:(NSString *)argument {
    return [argument isEqualToString:@"--bundle-id"] ||
           [argument isEqualToString:@"-b"] ||
           [argument isEqualToString:@"--transport"] ||
           [argument isEqualToString:@"--port"] ||
           [argument isEqualToString:@"--device-id"];
}

+ (BOOL)consumeSelectionArgument:(NSString *)argument
                       arguments:(NSArray<NSString *> *)arguments
                           index:(NSUInteger *)index
                       selection:(LKCLIAppSelection *)selection
                    errorMessage:(NSString **)errorMessage {
    if (index == NULL || selection == nil) {
        if (errorMessage) {
            *errorMessage = @"internal argument parser error";
        }
        return NO;
    }

    NSString *value = nil;
    if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:index value:&value errorMessage:errorMessage]) {
        return NO;
    }

    if ([argument isEqualToString:@"--bundle-id"] || [argument isEqualToString:@"-b"]) {
        selection.bundleID = value;
        return YES;
    }
    if ([argument isEqualToString:@"--transport"]) {
        if (![value isEqualToString:@"simulator"] && ![value isEqualToString:@"usb"]) {
            if (errorMessage) {
                *errorMessage = @"error: --transport must be 'simulator' or 'usb'";
            }
            return NO;
        }
        selection.transport = value;
        return YES;
    }
    if ([argument isEqualToString:@"--port"]) {
        NSInteger port = 0;
        if (![LKCLIArgumentParser parseIntegerValue:value min:1 max:65535 result:&port]) {
            if (errorMessage) {
                *errorMessage = @"error: --port must be an integer between 1 and 65535";
            }
            return NO;
        }
        selection.port = @(port);
        return YES;
    }
    if ([argument isEqualToString:@"--device-id"]) {
        NSInteger deviceID = 0;
        if (![LKCLIArgumentParser parseIntegerValue:value min:0 max:NSIntegerMax result:&deviceID]) {
            if (errorMessage) {
                *errorMessage = @"error: --device-id must be a non-negative integer";
            }
            return NO;
        }
        selection.deviceID = @(deviceID);
        return YES;
    }

    if (errorMessage) {
        *errorMessage = [NSString stringWithFormat:@"error: unknown app selector option '%@'", argument];
    }
    return NO;
}

+ (NSArray<LKCLIConnectedApp *> *)appsFromAppsValue:(id)appsValue
                                           selection:(LKCLIAppSelection *)selection
                                includeServerErrors:(BOOL)includeServerErrors {
    if (![appsValue isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<LKCLIConnectedApp *> *matches = [NSMutableArray array];
    for (LKCLIConnectedApp *app in (NSArray *)appsValue) {
        if (![app isKindOfClass:[LKCLIConnectedApp class]]) {
            continue;
        }
        if (!includeServerErrors && app.serverVersionError) {
            continue;
        }
        if ([self app:app matchesSelection:selection]) {
            [matches addObject:app];
        }
    }
    return matches.copy;
}

+ (BOOL)app:(LKCLIConnectedApp *)app matchesSelection:(LKCLIAppSelection *)selection {
    if (selection.bundleID.length > 0 && ![app.appInfo.appBundleIdentifier isEqualToString:selection.bundleID]) {
        return NO;
    }
    if (selection.transport.length > 0 && ![app.transport isEqualToString:selection.transport]) {
        return NO;
    }
    if (selection.port && app.port != selection.port.integerValue) {
        return NO;
    }
    if (selection.deviceID && ![app.deviceID isEqual:selection.deviceID]) {
        return NO;
    }
    return YES;
}

+ (NSString *)selectionHelpSuffix {
    return @" [--transport simulator|usb] [--port <port>] [--device-id <id>]";
}

- (LKCLIConnectedApp *)selectAppFromAppsValue:(id)appsValue
                                    selection:(LKCLIAppSelection *)selection
                                     exitCode:(LKCLIExitCode *)exitCode {
    NSArray<LKCLIConnectedApp *> *matchingApps = [LKCLIAppSelector appsFromAppsValue:appsValue selection:selection includeServerErrors:NO];
    if (matchingApps.count == 0) {
        if (exitCode) {
            *exitCode = LKCLIExitCodeNoApp;
        }
        [LKCLIStdIO writeError:@"error: no inspectable app found for %@", [self selectionDescription:selection]];
        return nil;
    }
    if (matchingApps.count > 1) {
        if (exitCode) {
            *exitCode = LKCLIExitCodeAmbiguousApp;
        }
        [LKCLIStdIO writeError:@"error: multiple apps matched %@", [self selectionDescription:selection]];
        [LKCLIStdIO writeError:@"hint: add --transport, --port, or --device-id to choose one"];
        return nil;
    }

    if (exitCode) {
        *exitCode = LKCLIExitCodeOK;
    }
    return matchingApps.firstObject;
}

- (NSString *)selectionDescription:(LKCLIAppSelection *)selection {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (selection.bundleID.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"bundle id '%@'", selection.bundleID]];
    }
    if (selection.transport.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"transport '%@'", selection.transport]];
    }
    if (selection.port) {
        [parts addObject:[NSString stringWithFormat:@"port %@", selection.port]];
    }
    if (selection.deviceID) {
        [parts addObject:[NSString stringWithFormat:@"device id %@", selection.deviceID]];
    }
    if (parts.count == 0) {
        return @"the given selector";
    }
    return [parts componentsJoinedByString:@", "];
}

@end
