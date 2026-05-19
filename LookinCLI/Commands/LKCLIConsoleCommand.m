#import "LKCLIConsoleCommand.h"
#import "LKCLIAppScanner.h"
#import "LKCLIAppSelector.h"
#import "LKCLIArgumentParser.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinDefines.h"
#import "LookinObject.h"
#import <stdio.h>

@implementation LKCLIConsoleCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    unsigned long oid = 0;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
            [self printHelp];
            return LKCLIExitCodeOK;
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
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'ivista-lookin console --help'"];
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

    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    LKCLIExitCode selectionExitCode = LKCLIExitCodeOK;
    LKCLIConnectedApp *app = [self selectAppWithScanner:scanner selection:selection exitCode:&selectionExitCode];
    if (!app) {
        [scanner closeAllConnections];
        return selectionExitCode;
    }

    LookinObject *currentObject = nil;
    LKCLIExitCode objectExitCode = [self fetchObject:&currentObject oid:oid scanner:scanner app:app];
    if (objectExitCode != LKCLIExitCodeOK) {
        [scanner closeAllConnections];
        return objectExitCode;
    }

    [LKCLIStdIO writeOut:@"Connected to %@ (%@)", app.appInfo.appName ?: @"<unknown>", app.appInfo.appBundleIdentifier ?: @"<unknown>"];
    [self printCurrentObject:currentObject];
    [LKCLIStdIO writeOut:@"Type a property getter or no-argument method. Commands: help, selectors [filter], use <oid>, quit."];

    char *line = NULL;
    size_t linecap = 0;
    while (true) {
        printf("ivista-lookin:%lu> ", currentObject.oid);
        fflush(stdout);

        ssize_t length = getline(&line, &linecap, stdin);
        if (length < 0) {
            break;
        }

        NSString *input = [[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (input.length == 0) {
            continue;
        }
        if ([input isEqualToString:@"quit"] || [input isEqualToString:@"exit"]) {
            break;
        }
        if ([input isEqualToString:@"help"]) {
            [self printConsoleHelp];
            continue;
        }
        if ([input hasPrefix:@"use "]) {
            NSString *oidText = [[input substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            unsigned long nextOID = 0;
            if (![LKCLIDisplayItemFetcher parseOIDValue:oidText oid:&nextOID]) {
                [LKCLIStdIO writeError:@"error: use requires a positive integer oid"];
                continue;
            }
            LookinObject *nextObject = nil;
            LKCLIExitCode exitCode = [self fetchObject:&nextObject oid:nextOID scanner:scanner app:app];
            if (exitCode == LKCLIExitCodeOK) {
                currentObject = nextObject;
                [self printCurrentObject:currentObject];
            }
            continue;
        }
        if ([input isEqualToString:@"selectors"] || [input hasPrefix:@"selectors "]) {
            NSString *filter = nil;
            if ([input hasPrefix:@"selectors "]) {
                filter = [[input substringFromIndex:@"selectors ".length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
            [self printSelectorsForObject:currentObject filter:filter scanner:scanner app:app];
            continue;
        }
        if ([input containsString:@":"]) {
            [LKCLIStdIO writeError:@"error: Lookin console only supports no-argument methods"];
            continue;
        }
        if ([input containsString:@"."]) {
            [LKCLIStdIO writeError:@"error: dot expressions are not supported yet; input a direct property or method name"];
            continue;
        }

        [self invokeSelector:input oid:currentObject.oid scanner:scanner app:app];
    }

    if (line) {
        free(line);
    }
    [scanner closeAllConnections];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  ivista-lookin console --bundle-id <bundle-id> --oid <oid> [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Open a lightweight Lookin console for direct property getters and no-argument methods."];
}

+ (void)printConsoleHelp {
    [LKCLIStdIO writeOut:
     @"Commands:\n"
      "  <name>             Evaluate a direct property getter or no-argument method\n"
      "  selectors [filter] List selectors for the current object's class\n"
      "  use <oid>          Switch the console target object\n"
      "  help               Show this help\n"
      "  quit               Exit the console"];
}

+ (LKCLIConnectedApp *)selectAppWithScanner:(LKCLIAppScanner *)scanner selection:(LKCLIAppSelection *)selection exitCode:(LKCLIExitCode *)exitCode {
    id appsValue = nil;
    NSError *appsError = nil;
    BOOL fetchedApps = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:10 value:&appsValue error:&appsError];
    if (!fetchedApps) {
        [LKCLIStdIO writeError:@"error: %@", appsError.localizedDescription ?: @"failed to fetch apps"];
        if (exitCode) {
            *exitCode = LKCLIExitCodeConnection;
        }
        return nil;
    }

    LKCLIExitCode selectionExitCode = LKCLIExitCodeOK;
    LKCLIConnectedApp *app = [[LKCLIAppSelector new] selectAppFromAppsValue:appsValue selection:selection exitCode:&selectionExitCode];
    if (exitCode) {
        *exitCode = selectionExitCode;
    }
    return app;
}

+ (LKCLIExitCode)fetchObject:(LookinObject **)object oid:(unsigned long)oid scanner:(LKCLIAppScanner *)scanner app:(LKCLIConnectedApp *)app {
    id objectValue = nil;
    NSError *objectError = nil;
    BOOL fetchedObject = [LKCLISignalRunner waitForSignal:[scanner fetchObjectWithOID:oid forApp:app] timeout:10 value:&objectValue error:&objectError];
    if (!fetchedObject) {
        [LKCLIStdIO writeError:@"error: %@", objectError.localizedDescription ?: @"failed to fetch object"];
        return objectError.code == LookinErrCode_ObjectNotFound ? LKCLIExitCodeObjectNotFound : LKCLIExitCodeConnection;
    }
    if (![objectValue isKindOfClass:[LookinObject class]]) {
        [LKCLIStdIO writeError:@"error: invalid object response"];
        return LKCLIExitCodeGeneralError;
    }
    if (object) {
        *object = objectValue;
    }
    return LKCLIExitCodeOK;
}

+ (void)printCurrentObject:(LookinObject *)object {
    [LKCLIStdIO writeOut:@"Current object: oid=%lu class=%@ memory=%@", object.oid, object.rawClassName ?: @"<unknown>", object.memoryAddress ?: @"<unknown>"];
}

+ (void)printSelectorsForObject:(LookinObject *)object filter:(NSString *)filter scanner:(LKCLIAppScanner *)scanner app:(LKCLIConnectedApp *)app {
    if (object.rawClassName.length == 0) {
        [LKCLIStdIO writeError:@"error: current object has no class name"];
        return;
    }

    id selectorsValue = nil;
    NSError *selectorsError = nil;
    BOOL fetchedSelectors = [LKCLISignalRunner waitForSignal:[scanner fetchSelectorNamesWithClass:object.rawClassName hasArg:NO forApp:app] timeout:12 value:&selectorsValue error:&selectorsError];
    if (!fetchedSelectors) {
        [LKCLIStdIO writeError:@"error: %@", selectorsError.localizedDescription ?: @"failed to fetch selectors"];
        return;
    }
    if (![selectorsValue isKindOfClass:[NSArray class]]) {
        [LKCLIStdIO writeError:@"error: invalid selectors response"];
        return;
    }

    NSMutableArray<NSString *> *selectors = [NSMutableArray array];
    for (id item in (NSArray *)selectorsValue) {
        if (![item isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *selector = item;
        if (filter.length > 0 && [selector rangeOfString:filter options:NSCaseInsensitiveSearch].location == NSNotFound) {
            continue;
        }
        [selectors addObject:selector];
    }
    [selectors sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *selector in selectors) {
        [LKCLIStdIO writeOut:@"%@", selector];
    }
    [LKCLIStdIO writeOut:@"%lu selector(s)", (unsigned long)selectors.count];
}

+ (void)invokeSelector:(NSString *)selectorName oid:(unsigned long)oid scanner:(LKCLIAppScanner *)scanner app:(LKCLIConnectedApp *)app {
    id invocationValue = nil;
    NSError *invocationError = nil;
    BOOL invoked = [LKCLISignalRunner waitForSignal:[scanner invokeMethodWithOID:oid selectorName:selectorName forApp:app] timeout:12 value:&invocationValue error:&invocationError];
    if (!invoked) {
        [LKCLIStdIO writeError:@"error: %@", invocationError.localizedDescription ?: @"failed to invoke method"];
        return;
    }
    if (![invocationValue isKindOfClass:[NSDictionary class]]) {
        [LKCLIStdIO writeError:@"error: invalid invocation response"];
        return;
    }

    NSDictionary *result = invocationValue;
    NSString *description = [result[@"description"] isKindOfClass:[NSString class]] ? result[@"description"] : nil;
    if ([description isEqualToString:LookinStringFlag_VoidReturn]) {
        description = @"The method was invoked successfully and no value was returned.";
    }
    if (description.length > 0) {
        [LKCLIStdIO writeOut:@"%@", description];
    } else {
        [LKCLIStdIO writeOut:@"<nil>"];
    }

    id object = result[@"object"];
    if ([object isKindOfClass:[LookinObject class]]) {
        LookinObject *returnObject = object;
        [LKCLIStdIO writeOut:@"return object: oid=%lu class=%@ memory=%@", returnObject.oid, returnObject.rawClassName ?: @"<unknown>", returnObject.memoryAddress ?: @"<unknown>"];
    }
}

@end
