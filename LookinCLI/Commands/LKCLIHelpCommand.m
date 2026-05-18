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
      "  lookin apps [--json]\n"
      "\n"
      "Planned commands:\n"
      "  lookin inspect --bundle-id <bundle-id> [--json]\n"
      "  lookin tree --bundle-id <bundle-id> [--json]\n"
      "\n"
      "This build includes app discovery. Tree and inspection commands are planned next."];
    return LKCLIExitCodeOK;
}

@end
