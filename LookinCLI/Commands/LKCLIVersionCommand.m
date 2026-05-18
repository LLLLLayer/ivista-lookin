#import "LKCLIVersionCommand.h"
#import "LKCLIVersionProvider.h"
#import "LKCLIStdIO.h"

@implementation LKCLIVersionCommand

+ (LKCLIExitCode)run {
    [LKCLIStdIO writeOut:@"LookinCLI %@", [LKCLIVersionProvider cliVersion]];
    [LKCLIStdIO writeOut:@"Protocol %@", [LKCLIVersionProvider protocolVersionDescription]];
    [LKCLIStdIO writeOut:@"Architecture %@", [LKCLIVersionProvider architectureName]];
    return LKCLIExitCodeOK;
}

@end
