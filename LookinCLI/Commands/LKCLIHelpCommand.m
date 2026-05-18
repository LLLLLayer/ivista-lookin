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
      "  lookin tree --bundle-id <bundle-id> [--json] [--depth N]\n"
      "\n"
      "Planned commands:\n"
      "  lookin inspect --bundle-id <bundle-id> [--json]\n"
      "\n"
      "This build includes app discovery and hierarchy tree output. Inspection commands are planned next."];
    return LKCLIExitCodeOK;
}

@end
