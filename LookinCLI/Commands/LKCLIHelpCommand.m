#import "LKCLIHelpCommand.h"
#import "LKCLIStdIO.h"

@implementation LKCLIHelpCommand

+ (LKCLIExitCode)run {
    [LKCLIStdIO writeOut:
     @"LookinCLI\n"
      "\n"
      "Usage:\n"
      "  ivista-lookin --help\n"
      "  ivista-lookin --version\n"
      "  ivista-lookin doctor\n"
      "  ivista-lookin apps [--json] [--bundle-id <bundle-id>] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin tree --bundle-id <bundle-id> [--json] [--depth N] [--filter <text>] [--oid <oid>] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin find --bundle-id <bundle-id> <query> [--json] [--limit N] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin inspect --bundle-id <bundle-id> --oid <oid> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin attrs --bundle-id <bundle-id> --oid <oid> [--group <filter>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin screenshot --bundle-id <bundle-id> --oid <oid> --out <path> [--type group|solo] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin export --bundle-id <bundle-id> --out <file.lookin> [--compression <0.01-1>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin read <file.lookin> [summary|tree|find|inspect|attrs] [options]\n"
      "  ivista-lookin selectors --bundle-id <bundle-id> (--class <class-name> | --oid <oid>) [--with-args] [--filter <text>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin call --bundle-id <bundle-id> --oid <oid> --selector <selector> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin eval --bundle-id <bundle-id> --oid <oid> <property-or-method> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin console --bundle-id <bundle-id> --oid <oid> [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin set --bundle-id <bundle-id> --oid <oid> --attr <identifier> --value <value> [--dry-run] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "This build includes app discovery, app selection filters, hierarchy tree output, hierarchy search, object inspection, attribute queries, screenshot export, .lookin snapshot export and offline read, selector listing, no-argument method invocation, console-style evaluation, and built-in attribute modification."];
    return LKCLIExitCodeOK;
}

@end
