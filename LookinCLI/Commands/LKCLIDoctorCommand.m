#import "LKCLIDoctorCommand.h"
#import "LKCLIVersionProvider.h"
#import "LKCLIStdIO.h"
#import "LookinDefines.h"

@implementation LKCLIDoctorCommand

+ (LKCLIExitCode)run {
    [LKCLIStdIO writeOut:@"LookinCLI: ok"];
    [LKCLIStdIO writeOut:@"Version: %@", [LKCLIVersionProvider cliVersion]];
    [LKCLIStdIO writeOut:@"Protocol: %@", [LKCLIVersionProvider protocolVersionDescription]];
    [LKCLIStdIO writeOut:@"Architecture: %@", [LKCLIVersionProvider architectureName]];
    [LKCLIStdIO writeOut:@"Simulator ports: %d-%d", LookinSimulatorIPv4PortNumberStart, LookinSimulatorIPv4PortNumberEnd];
    [LKCLIStdIO writeOut:@"USB ports: %d-%d", LookinUSBDeviceIPv4PortNumberStart, LookinUSBDeviceIPv4PortNumberEnd];
    [LKCLIStdIO writeOut:@"LookinShared: ok"];
    [LKCLIStdIO writeOut:@"ReactiveObjC: ok"];
    return LKCLIExitCodeOK;
}

@end
