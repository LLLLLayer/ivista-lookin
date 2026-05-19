#import "LKCLISelectorsCommand.h"
#import "LKCLIAppScanner.h"
#import "LKCLIAppSelector.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinDefines.h"
#import "LookinObject.h"

@implementation LKCLISelectorsCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    NSString *className = nil;
    NSString *filter = nil;
    unsigned long oid = 0;
    BOOL hasArg = NO;
    BOOL json = NO;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([argument isEqualToString:@"--with-args"]) {
            hasArg = YES;
        } else if ([LKCLIAppSelector isSelectionArgument:argument]) {
            NSString *errorMessage = nil;
            if (![LKCLIAppSelector consumeSelectionArgument:argument arguments:arguments index:&idx selection:selection errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage ?: @"error: invalid app selector option"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--class"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --class requires a value"];
                return LKCLIExitCodeUsage;
            }
            className = arguments[++idx];
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
        } else if ([argument isEqualToString:@"--filter"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --filter requires a value"];
                return LKCLIExitCodeUsage;
            }
            filter = arguments[++idx];
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'ivista-lookin selectors --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (className.length == 0 && oid == 0) {
        [LKCLIStdIO writeError:@"error: --class or --oid is required"];
        return LKCLIExitCodeUsage;
    }

    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    LKCLIExitCode selectionExitCode = LKCLIExitCodeOK;
    LKCLIConnectedApp *app = [self selectAppWithScanner:scanner selection:selection exitCode:&selectionExitCode];
    if (!app) {
        [scanner closeAllConnections];
        return selectionExitCode;
    }

    if (className.length == 0) {
        id objectValue = nil;
        NSError *objectError = nil;
        BOOL fetchedObject = [LKCLISignalRunner waitForSignal:[scanner fetchObjectWithOID:oid forApp:app] timeout:10 value:&objectValue error:&objectError];
        if (!fetchedObject) {
            [scanner closeAllConnections];
            [LKCLIStdIO writeError:@"error: %@", objectError.localizedDescription ?: @"failed to fetch object"];
            return objectError.code == LookinErrCode_ObjectNotFound ? LKCLIExitCodeObjectNotFound : LKCLIExitCodeConnection;
        }
        if (![objectValue isKindOfClass:[LookinObject class]]) {
            [scanner closeAllConnections];
            [LKCLIStdIO writeError:@"error: invalid object response"];
            return LKCLIExitCodeGeneralError;
        }
        className = ((LookinObject *)objectValue).rawClassName;
    }

    id selectorsValue = nil;
    NSError *selectorsError = nil;
    BOOL fetchedSelectors = [LKCLISignalRunner waitForSignal:[scanner fetchSelectorNamesWithClass:className hasArg:hasArg forApp:app] timeout:12 value:&selectorsValue error:&selectorsError];
    [scanner closeAllConnections];

    if (!fetchedSelectors) {
        [LKCLIStdIO writeError:@"error: %@", selectorsError.localizedDescription ?: @"failed to fetch selectors"];
        return LKCLIExitCodeConnection;
    }
    if (![selectorsValue isKindOfClass:[NSArray class]]) {
        [LKCLIStdIO writeError:@"error: invalid selectors response"];
        return LKCLIExitCodeGeneralError;
    }

    NSArray<NSString *> *selectors = [self sortedStringArrayFromValue:selectorsValue];
    selectors = [self selectors:selectors matchingFilter:filter];
    if (json) {
        return [self printJSONWithApp:app className:className oid:oid hasArg:hasArg filter:filter selectors:selectors];
    }
    [self printTextWithApp:app className:className oid:oid hasArg:hasArg filter:filter selectors:selectors];
    return LKCLIExitCodeOK;
}

+ (LKCLIConnectedApp *)selectAppWithScanner:(LKCLIAppScanner *)scanner selection:(LKCLIAppSelection *)selection exitCode:(LKCLIExitCode *)exitCode {
    id appsValue = nil;
    NSError *appsError = nil;
    BOOL fetchedApps = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:10 value:&appsValue error:&appsError];
    if (!fetchedApps) {
        [LKCLIStdIO writeError:@"error: %@", appsError.localizedDescription ?: @"failed to fetch apps"];
        if (exitCode) {
            *exitCode = LKCLIExitCodeConnection;
        }
        return nil;
    }
    LKCLIExitCode selectionExitCode = LKCLIExitCodeOK;
    LKCLIConnectedApp *app = [[LKCLIAppSelector new] selectAppFromAppsValue:appsValue selection:selection exitCode:&selectionExitCode];
    if (exitCode) {
        *exitCode = selectionExitCode;
    }
    return app;
}

+ (NSArray<NSString *> *)sortedStringArrayFromValue:(id)value {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (id item in (NSArray *)value) {
        if ([item isKindOfClass:[NSString class]]) {
            [strings addObject:item];
        }
    }
    return [strings sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (NSArray<NSString *> *)selectors:(NSArray<NSString *> *)selectors matchingFilter:(NSString *)filter {
    if (filter.length == 0) {
        return selectors;
    }

    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *selector in selectors) {
        if ([selector rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [matches addObject:selector];
        }
    }
    return matches.copy;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  ivista-lookin selectors --bundle-id <bundle-id> (--class <class-name> | --oid <oid>) [--with-args] [--filter <text>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Fetch selector names for a class or an object. By default only no-argument methods are returned."];
}

+ (void)printTextWithApp:(LKCLIConnectedApp *)app
               className:(NSString *)className
                     oid:(unsigned long)oid
                  hasArg:(BOOL)hasArg
                  filter:(NSString *)filter
               selectors:(NSArray<NSString *> *)selectors {
    [LKCLIStdIO writeOut:@"%@ (%@)", app.appInfo.appName ?: @"<unknown>", app.appInfo.appBundleIdentifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"class: %@", className ?: @"<unknown>"];
    if (oid != 0) {
        [LKCLIStdIO writeOut:@"oid: %lu", oid];
    }
    [LKCLIStdIO writeOut:@"mode: %@", hasArg ? @"with arguments" : @"no arguments"];
    if (filter.length > 0) {
        [LKCLIStdIO writeOut:@"filter: %@", filter];
    }
    [LKCLIStdIO writeOut:@"selectors: %lu", (unsigned long)selectors.count];
    for (NSString *selector in selectors) {
        [LKCLIStdIO writeOut:@"  %@", selector];
    }
}

+ (LKCLIExitCode)printJSONWithApp:(LKCLIConnectedApp *)app
                         className:(NSString *)className
                               oid:(unsigned long)oid
                            hasArg:(BOOL)hasArg
                            filter:(NSString *)filter
                         selectors:(NSArray<NSString *> *)selectors {
    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"app"] = @{
        @"name": app.appInfo.appName ?: [NSNull null],
        @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
        @"device": app.appInfo.deviceDescription ?: [NSNull null],
        @"os": app.appInfo.osDescription ?: [NSNull null],
    };
    root[@"className"] = className ?: [NSNull null];
    root[@"oid"] = oid == 0 ? [NSNull null] : @(oid);
    root[@"hasArguments"] = @(hasArg);
    root[@"filter"] = filter ?: [NSNull null];
    root[@"selectors"] = selectors ?: @[];

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
