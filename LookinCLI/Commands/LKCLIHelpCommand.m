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
      "  lookin inspect --bundle-id <bundle-id> --oid <oid> [--json]\n"
      "\n"
      "Planned commands:\n"
      "  lookin attrs --bundle-id <bundle-id> --oid <oid> [--json]\n"
      "\n"
      "This build includes app discovery, hierarchy tree output, and object inspection."];
    return LKCLIExitCodeOK;
}

@end
