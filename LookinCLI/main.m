#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"
#import "LKCLIHelpCommand.h"
#import "LKCLIVersionCommand.h"
#import "LKCLIDoctorCommand.h"
#import "LKCLIAppsCommand.h"
#import "LKCLITreeCommand.h"
#import "LKCLIInspectCommand.h"
#import "LKCLIAttrsCommand.h"
#import "LKCLIScreenshotCommand.h"
#import "LKCLIExportCommand.h"
#import "LKCLISelectorsCommand.h"
#import "LKCLICallCommand.h"
#import "LKCLIProcessLock.h"
#import "LKCLIStdIO.h"

static NSArray<NSString *> *LKCLIArguments(int argc, const char * argv[]) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithCapacity:MAX(argc - 1, 0)];
    for (int i = 1; i < argc; i++) {
        [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
    }
    return arguments.copy;
}

static BOOL LKCLIArgumentsContainHelp(NSArray<NSString *> *arguments) {
    for (NSString *argument in arguments) {
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            return YES;
        }
    }
    return NO;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *arguments = LKCLIArguments(argc, argv);
        NSString *command = arguments.firstObject;
        NSArray<NSString *> *commandArguments = arguments.count > 1 ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)] : @[];

        if (!command || [command isEqualToString:@"--help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"help"]) {
            return (int)[LKCLIHelpCommand run];
        }

        if ([command isEqualToString:@"--version"] || [command isEqualToString:@"version"]) {
            return (int)[LKCLIVersionCommand run];
        }

        if ([command isEqualToString:@"doctor"]) {
            return (int)[LKCLIDoctorCommand run];
        }

        if ([command isEqualToString:@"apps"]) {
            if (LKCLIArgumentsContainHelp(commandArguments)) {
                return (int)[LKCLIAppsCommand runWithArguments:commandArguments];
            }
            return (int)[LKCLIProcessLock runDeviceCommandWithBlock:^LKCLIExitCode{
                return [LKCLIAppsCommand runWithArguments:commandArguments];
            }];
        }

        if ([command isEqualToString:@"tree"]) {
            if (LKCLIArgumentsContainHelp(commandArguments)) {
                return (int)[LKCLITreeCommand runWithArguments:commandArguments];
            }
            return (int)[LKCLIProcessLock runDeviceCommandWithBlock:^LKCLIExitCode{
                return [LKCLITreeCommand runWithArguments:commandArguments];
            }];
        }

        if ([command isEqualToString:@"inspect"]) {
            if (LKCLIArgumentsContainHelp(commandArguments)) {
                return (int)[LKCLIInspectCommand runWithArguments:commandArguments];
            }
            return (int)[LKCLIProcessLock runDeviceCommandWithBlock:^LKCLIExitCode{
                return [LKCLIInspectCommand runWithArguments:commandArguments];
            }];
        }

        if ([command isEqualToString:@"attrs"]) {
            if (LKCLIArgumentsContainHelp(commandArguments)) {
                return (int)[LKCLIAttrsCommand runWithArguments:commandArguments];
            }
            return (int)[LKCLIProcessLock runDeviceCommandWithBlock:^LKCLIExitCode{
                return [LKCLIAttrsCommand runWithArguments:commandArguments];
            }];
        }

        if ([command isEqualToString:@"screenshot"]) {
            if (LKCLIArgumentsContainHelp(commandArguments)) {
                return (int)[LKCLIScreenshotCommand runWithArguments:commandArguments];
            }
            return (int)[LKCLIProcessLock runDeviceCommandWithBlock:^LKCLIExitCode{
                return [LKCLIScreenshotCommand runWithArguments:commandArguments];
            }];
        }

        if ([command isEqualToString:@"export"]) {
            if (LKCLIArgumentsContainHelp(commandArguments)) {
                return (int)[LKCLIExportCommand runWithArguments:commandArguments];
            }
            return (int)[LKCLIProcessLock runDeviceCommandWithBlock:^LKCLIExitCode{
                return [LKCLIExportCommand runWithArguments:commandArguments];
            }];
        }

        if ([command isEqualToString:@"selectors"]) {
            if (LKCLIArgumentsContainHelp(commandArguments)) {
                return (int)[LKCLISelectorsCommand runWithArguments:commandArguments];
            }
            return (int)[LKCLIProcessLock runDeviceCommandWithBlock:^LKCLIExitCode{
                return [LKCLISelectorsCommand runWithArguments:commandArguments];
            }];
        }

        if ([command isEqualToString:@"call"]) {
            if (LKCLIArgumentsContainHelp(commandArguments)) {
                return (int)[LKCLICallCommand runWithArguments:commandArguments];
            }
            return (int)[LKCLIProcessLock runDeviceCommandWithBlock:^LKCLIExitCode{
                return [LKCLICallCommand runWithArguments:commandArguments];
            }];
        }

        [LKCLIStdIO writeError:@"error: unknown command '%@'", command];
        [LKCLIStdIO writeError:@"hint: run 'lookin --help'"];
        return (int)LKCLIExitCodeUsage;
    }
}
