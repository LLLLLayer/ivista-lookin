#import "LKCLILookinAppGuard.h"
#import "LKCLIStdIO.h"
#import <AppKit/AppKit.h>

static NSString *const LKCLILookinAppBundleIdentifier = @"hughkli.Lookin";

@implementation LKCLILookinAppGuard

+ (BOOL)isLookinAppRunning {
    return [self runningLookinApplications].count > 0;
}

+ (NSString *)runningAppSummary {
    NSArray<NSRunningApplication *> *applications = [self runningLookinApplications];
    if (applications.count == 0) {
        return @"not running";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:applications.count];
    for (NSRunningApplication *application in applications) {
        NSString *name = application.localizedName.length ? application.localizedName : @"Lookin";
        [parts addObject:[NSString stringWithFormat:@"%@ (pid %d)", name, application.processIdentifier]];
    }
    return [parts componentsJoinedByString:@", "];
}

+ (void)warnIfLookinAppRunning {
    if (![self isLookinAppRunning]) {
        return;
    }

    [LKCLIStdIO writeError:@"warning: Lookin.app is running: %@", [self runningAppSummary]];
    [LKCLIStdIO writeError:@"hint: current LookinServer supports one client session per target app; quit Lookin.app if ivista-lookin cannot find or connect to an app"];
}

+ (NSArray<NSRunningApplication *> *)runningLookinApplications {
    NSMutableArray<NSRunningApplication *> *matches = [NSMutableArray array];
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSArray<NSRunningApplication *> *bundleMatches = [NSRunningApplication runningApplicationsWithBundleIdentifier:LKCLILookinAppBundleIdentifier];
    [matches addObjectsFromArray:bundleMatches];

    for (NSRunningApplication *application in workspace.runningApplications) {
        if ([matches containsObject:application]) {
            continue;
        }
        if ([self applicationLooksLikeLookin:application]) {
            [matches addObject:application];
        }
    }
    return matches.copy;
}

+ (BOOL)applicationLooksLikeLookin:(NSRunningApplication *)application {
    if ([application.bundleIdentifier isEqualToString:LKCLILookinAppBundleIdentifier]) {
        return YES;
    }
    if ([application.localizedName isEqualToString:@"Lookin"]) {
        return YES;
    }
    if ([application.bundleURL.lastPathComponent isEqualToString:@"Lookin.app"]) {
        return YES;
    }
    if ([application.executableURL.path hasSuffix:@"/Lookin.app/Contents/MacOS/Lookin"]) {
        return YES;
    }
    return NO;
}

@end
