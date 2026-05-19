#import "LKCLICallCommand.h"
#import "LKCLIAppScanner.h"
#import "LKCLIAppSelector.h"
#import "LKCLIArgumentParser.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLIJSONWriter.h"
#import "LKCLIOnlineCommandRunner.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinDefines.h"
#import "LookinObject.h"

@implementation LKCLICallCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    NSString *selectorName = nil;
    unsigned long oid = 0;
    BOOL json = NO;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([LKCLIAppSelector isSelectionArgument:argument]) {
            NSString *errorMessage = nil;
            if (![LKCLIAppSelector consumeSelectionArgument:argument arguments:arguments index:&idx selection:selection errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage ?: @"error: invalid app selector option"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--oid"]) {
            NSString *oidValue = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&oidValue errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            if (![LKCLIDisplayItemFetcher parseOIDValue:oidValue oid:&oid]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--selector"]) {
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&selectorName errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'ivista-lookin call --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (oid == 0) {
        [LKCLIStdIO writeError:@"error: --oid is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin tree --bundle-id %@' to find object ids", selection.bundleID];
        return LKCLIExitCodeUsage;
    }
    if (selectorName.length == 0) {
        [LKCLIStdIO writeError:@"error: --selector is required"];
        return LKCLIExitCodeUsage;
    }
    if ([selectorName containsString:@":"]) {
        [LKCLIStdIO writeError:@"error: LookinCLI only supports no-argument selectors for now"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin selectors --bundle-id %@ --oid %lu' to list supported methods", selection.bundleID, oid];
        return LKCLIExitCodeUnsupported;
    }

    return [LKCLIOnlineCommandRunner withSelectedAppForSelection:selection appsTimeout:10 body:^LKCLIExitCode(LKCLIAppScanner *scanner, LKCLIConnectedApp *app) {
        id invocationValue = nil;
        NSError *invocationError = nil;
        BOOL invoked = [LKCLISignalRunner waitForSignal:[scanner invokeMethodWithOID:oid selectorName:selectorName forApp:app] timeout:12 value:&invocationValue error:&invocationError];
        if (!invoked) {
            [LKCLIStdIO writeError:@"error: %@", invocationError.localizedDescription ?: @"failed to invoke method"];
            return invocationError.code == LookinErrCode_ObjectNotFound ? LKCLIExitCodeObjectNotFound : LKCLIExitCodeConnection;
        }
        if (![invocationValue isKindOfClass:[NSDictionary class]]) {
            [LKCLIStdIO writeError:@"error: invalid invocation response"];
            return LKCLIExitCodeGeneralError;
        }

        NSDictionary *result = (NSDictionary *)invocationValue;
        if (json) {
            return [self printJSONWithApp:app oid:oid selectorName:selectorName result:result];
        }
        [self printTextWithApp:app oid:oid selectorName:selectorName result:result];
        return LKCLIExitCodeOK;
    }];
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  ivista-lookin call --bundle-id <bundle-id> --oid <oid> --selector <selector> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Invoke a no-argument selector on an object."];
}

+ (void)printTextWithApp:(LKCLIConnectedApp *)app
                     oid:(unsigned long)oid
            selectorName:(NSString *)selectorName
                  result:(NSDictionary *)result {
    NSString *description = [self returnDescriptionFromResult:result];
    LookinObject *object = [self returnObjectFromResult:result];

    [LKCLIStdIO writeOut:@"%@ (%@)", app.appInfo.appName ?: @"<unknown>", app.appInfo.appBundleIdentifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"oid: %lu", oid];
    [LKCLIStdIO writeOut:@"selector: %@", selectorName];
    [LKCLIStdIO writeOut:@"return: %@", description ?: @"<nil>"];
    if (object) {
        [LKCLIStdIO writeOut:@"return object:"];
        [LKCLIStdIO writeOut:@"  oid: %lu", object.oid];
        [LKCLIStdIO writeOut:@"  class: %@", object.rawClassName ?: @"<unknown>"];
        if (object.memoryAddress.length) {
            [LKCLIStdIO writeOut:@"  memory: %@", object.memoryAddress];
        }
    }
}

+ (LKCLIExitCode)printJSONWithApp:(LKCLIConnectedApp *)app
                               oid:(unsigned long)oid
                      selectorName:(NSString *)selectorName
                            result:(NSDictionary *)result {
    LookinObject *object = [self returnObjectFromResult:result];
    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"app"] = @{
        @"name": app.appInfo.appName ?: [NSNull null],
        @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
        @"device": app.appInfo.deviceDescription ?: [NSNull null],
        @"os": app.appInfo.osDescription ?: [NSNull null],
    };
    root[@"oid"] = @(oid);
    root[@"selector"] = selectorName ?: [NSNull null];
    root[@"returnDescription"] = [self returnDescriptionFromResult:result] ?: [NSNull null];
    root[@"returnObject"] = object ? [self JSONObjectForObject:object] : [NSNull null];

    return [LKCLIJSONWriter printJSONObject:root];
}

+ (NSString *)returnDescriptionFromResult:(NSDictionary *)result {
    NSString *description = [result[@"description"] isKindOfClass:[NSString class]] ? result[@"description"] : nil;
    if ([description isEqualToString:LookinStringFlag_VoidReturn]) {
        return @"The method was invoked successfully and no value was returned.";
    }
    return description;
}

+ (LookinObject *)returnObjectFromResult:(NSDictionary *)result {
    id object = result[@"object"];
    return [object isKindOfClass:[LookinObject class]] ? object : nil;
}

+ (NSDictionary *)JSONObjectForObject:(LookinObject *)object {
    return @{
        @"oid": @(object.oid),
        @"className": object.rawClassName ?: [NSNull null],
        @"memoryAddress": object.memoryAddress ?: [NSNull null],
        @"classChain": object.classChainList ?: @[],
        @"specialTrace": object.specialTrace ?: [NSNull null],
    };
}

@end
