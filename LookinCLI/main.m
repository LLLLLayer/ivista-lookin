#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"
#import "LKCLIHelpCommand.h"
#import "LKCLIVersionCommand.h"
#import "LKCLIDoctorCommand.h"
#import "LKCLIAppsCommand.h"
#import "LKCLIStdIO.h"

static NSArray<NSString *> *LKCLIArguments(int argc, const char * argv[]) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithCapacity:MAX(argc - 1, 0)];
    for (int i = 1; i < argc; i++) {
        [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
    }
    return arguments.copy;
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
            return (int)[LKCLIAppsCommand runWithArguments:commandArguments];
        }

        [LKCLIStdIO writeError:@"error: unknown command '%@'", command];
        [LKCLIStdIO writeError:@"hint: run 'lookin --help'"];
        return (int)LKCLIExitCodeUsage;
    }
}
