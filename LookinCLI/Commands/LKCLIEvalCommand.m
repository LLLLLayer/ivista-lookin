#import "LKCLIEvalCommand.h"
#import "LKCLIArgumentParser.h"
#import "LKCLICallCommand.h"
#import "LKCLIStdIO.h"

@implementation LKCLIEvalCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    NSMutableArray<NSString *> *callArguments = [NSMutableArray array];
    NSString *expression = nil;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        }

        if ([argument isEqualToString:@"--selector"]) {
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&expression errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            continue;
        }

        if ([argument isEqualToString:@"--bundle-id"] ||
            [argument isEqualToString:@"--transport"] ||
            [argument isEqualToString:@"--port"] ||
            [argument isEqualToString:@"--device-id"] ||
            [argument isEqualToString:@"--oid"]) {
            NSString *value = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&value errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            [callArguments addObject:argument];
            [callArguments addObject:value];
            continue;
        }

        if ([argument isEqualToString:@"--json"]) {
            [callArguments addObject:argument];
            continue;
        }

        if ([argument hasPrefix:@"-"]) {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'ivista-lookin eval --help'"];
            return LKCLIExitCodeUsage;
        }

        if (expression.length > 0) {
            [LKCLIStdIO writeError:@"error: eval accepts exactly one property or no-argument method name"];
            return LKCLIExitCodeUsage;
        }
        expression = argument;
    }

    if (expression.length == 0) {
        [LKCLIStdIO writeError:@"error: property or method name is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin eval --help'"];
        return LKCLIExitCodeUsage;
    }
    if ([expression containsString:@"."]) {
        [LKCLIStdIO writeError:@"error: Lookin console syntax does not support dot expressions yet"];
        [LKCLIStdIO writeError:@"hint: pass a direct getter or no-argument method name, such as 'frame' or 'description'"];
        return LKCLIExitCodeUnsupported;
    }

    [callArguments addObject:@"--selector"];
    [callArguments addObject:expression];
    return [LKCLICallCommand runWithArguments:callArguments];
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  ivista-lookin eval --bundle-id <bundle-id> --oid <oid> <property-or-method> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin eval --bundle-id <bundle-id> --oid <oid> --selector <selector> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Evaluate a direct property getter or no-argument method on an object. This is a console-friendly alias of 'ivista-lookin call'."];
}

@end
