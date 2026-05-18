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
      "  lookin attrs --bundle-id <bundle-id> --oid <oid> [--group <filter>] [--json]\n"
      "  lookin screenshot --bundle-id <bundle-id> --oid <oid> --out <path> [--type group|solo] [--json]\n"
      "\n"
      "Planned commands:\n"
      "  lookin export --bundle-id <bundle-id> --out <file.lookin>\n"
      "\n"
      "This build includes app discovery, hierarchy tree output, object inspection, attribute queries, and screenshot export."];
    return LKCLIExitCodeOK;
}

@end
