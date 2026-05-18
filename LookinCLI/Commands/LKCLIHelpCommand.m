#import "LKCLIHelpCommand.h"
#import "LKCLIStdIO.h"

@implementation LKCLIHelpCommand

+ (LKCLIExitCode)run {
    [LKCLIStdIO writeOut:
     @"LookinCLI\n"
      "\n"
      "Usage:\n"
      "  lookin --help\n"
      "  lookin --version\n"
      "  lookin doctor\n"
      "\n"
      "Planned commands:\n"
      "  lookin apps [--json]\n"
      "  lookin inspect --bundle-id <bundle-id> [--json]\n"
      "  lookin tree --bundle-id <bundle-id> [--json]\n"
      "\n"
      "This Phase 0 build only includes help, version, and doctor."];
    return LKCLIExitCodeOK;
}

@end
