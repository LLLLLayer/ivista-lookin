#import "LKCLIOnlineCommandRunner.h"
#import "LKCLIAppScanner.h"
#import "LKCLIAppSelector.h"
#import "LKCLIConnectedApp.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LookinHierarchyInfo.h"

@implementation LKCLIOnlineCommandRunner

+ (LKCLIExitCode)withSelectedAppForSelection:(LKCLIAppSelection *)selection
                                 appsTimeout:(NSTimeInterval)appsTimeout
                                        body:(LKCLISelectedAppBody)body {
    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    id appsValue = nil;
    NSError *appsError = nil;
    BOOL fetchedApps = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:appsTimeout value:&appsValue error:&appsError];
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

    LKCLIExitCode exitCode = body ? body(scanner, app) : LKCLIExitCodeOK;
    [scanner closeAllConnections];
    return exitCode;
}

+ (LKCLIExitCode)withHierarchyForSelection:(LKCLIAppSelection *)selection
                               appsTimeout:(NSTimeInterval)appsTimeout
                          hierarchyTimeout:(NSTimeInterval)hierarchyTimeout
                                      body:(LKCLIHierarchyBody)body {
    return [self withSelectedAppForSelection:selection appsTimeout:appsTimeout body:^LKCLIExitCode(LKCLIAppScanner *scanner, LKCLIConnectedApp *app) {
        id hierarchyValue = nil;
        NSError *hierarchyError = nil;
        BOOL fetchedHierarchy = [LKCLISignalRunner waitForSignal:[scanner fetchHierarchyForApp:app] timeout:hierarchyTimeout value:&hierarchyValue error:&hierarchyError];
        if (!fetchedHierarchy) {
            [LKCLIStdIO writeError:@"error: %@", hierarchyError.localizedDescription ?: @"failed to fetch hierarchy"];
            return LKCLIExitCodeConnection;
        }
        if (![hierarchyValue isKindOfClass:[LookinHierarchyInfo class]]) {
            [LKCLIStdIO writeError:@"error: invalid hierarchy response"];
            return LKCLIExitCodeGeneralError;
        }
        return body ? body(scanner, app, hierarchyValue) : LKCLIExitCodeOK;
    }];
}

@end
