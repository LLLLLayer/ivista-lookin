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
      "  lookin apps [--json] [--bundle-id <bundle-id>] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  lookin tree --bundle-id <bundle-id> [--json] [--depth N] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  lookin inspect --bundle-id <bundle-id> --oid <oid> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  lookin attrs --bundle-id <bundle-id> --oid <oid> [--group <filter>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  lookin screenshot --bundle-id <bundle-id> --oid <oid> --out <path> [--type group|solo] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  lookin export --bundle-id <bundle-id> --out <file.lookin> [--compression <0.01-1>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  lookin selectors --bundle-id <bundle-id> (--class <class-name> | --oid <oid>) [--with-args] [--filter <text>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  lookin call --bundle-id <bundle-id> --oid <oid> --selector <selector> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "This build includes app discovery, app selection filters, hierarchy tree output, object inspection, attribute queries, screenshot export, .lookin snapshot export, selector listing, and no-argument method invocation."];
    return LKCLIExitCodeOK;
}

@end
