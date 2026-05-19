#import "LKCLIReadCommand.h"
#import "LKCLIArgumentParser.h"
#import "LKCLIAttrsCommand.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLIInspectCommand.h"
#import "LKCLIJSONWriter.h"
#import "LKCLIStdIO.h"
#import "LKCLITreeCommand.h"
#import "LookinAppInfo.h"
#import "LookinAttributesGroup.h"
#import "LookinDisplayItem.h"
#import "LookinHierarchyFile.h"
#import "LookinHierarchyInfo.h"
#import "LookinObject.h"

@interface LKCLIReadCommand ()
@end

@implementation LKCLIReadCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    if (arguments.count == 0 || [LKCLIArgumentParser isHelpArgument:arguments.firstObject]) {
        [self printHelp];
        return LKCLIExitCodeOK;
    }

    NSString *path = arguments.firstObject;
    NSArray<NSString *> *remainingArguments = arguments.count > 1 ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)] : @[];
    NSString *subcommand = remainingArguments.firstObject ?: @"summary";
    NSArray<NSString *> *subcommandArguments = remainingArguments.count > 1 ? [remainingArguments subarrayWithRange:NSMakeRange(1, remainingArguments.count - 1)] : @[];

    NSError *error = nil;
    LookinHierarchyFile *file = [self hierarchyFileAtPath:path error:&error];
    if (!file) {
        [LKCLIStdIO writeError:@"error: %@", error.localizedDescription ?: @"failed to read .lookin file"];
        NSString *recovery = error.userInfo[NSLocalizedRecoverySuggestionErrorKey];
        if (recovery.length) {
            [LKCLIStdIO writeError:@"%@", recovery];
        }
        return LKCLIExitCodeGeneralError;
    }

    if ([subcommand isEqualToString:@"summary"]) {
        return [self runSummaryWithFile:file path:path arguments:subcommandArguments];
    }
    if ([subcommand isEqualToString:@"tree"]) {
        return [self runTreeWithFile:file arguments:subcommandArguments];
    }
    if ([subcommand isEqualToString:@"find"]) {
        return [self runFindWithFile:file arguments:subcommandArguments];
    }
    if ([subcommand isEqualToString:@"inspect"]) {
        return [self runInspectWithFile:file arguments:subcommandArguments];
    }
    if ([subcommand isEqualToString:@"attrs"]) {
        return [self runAttrsWithFile:file arguments:subcommandArguments];
    }

    [LKCLIStdIO writeError:@"error: unknown read subcommand '%@'", subcommand];
    [LKCLIStdIO writeError:@"hint: run 'ivista-lookin read --help'"];
    return LKCLIExitCodeUsage;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  ivista-lookin read <file.lookin> [summary] [--json]\n"
      "  ivista-lookin read <file.lookin> tree [--depth N] [--filter <text>] [--oid <oid>] [--json]\n"
      "  ivista-lookin read <file.lookin> find <query> [--limit N] [--json]\n"
      "  ivista-lookin read <file.lookin> find --oid <oid> [--json]\n"
      "  ivista-lookin read <file.lookin> inspect --oid <oid> [--json]\n"
      "  ivista-lookin read <file.lookin> attrs --oid <oid> [--group <filter>] [--json]\n"
      "\n"
      "Read an exported .lookin snapshot without connecting to a device."];
}

+ (LookinHierarchyFile *)hierarchyFileAtPath:(NSString *)path error:(NSError **)error {
    NSString *absolutePath = [self absolutePathForPath:path];
    NSData *data = [NSData dataWithContentsOfFile:absolutePath options:0 error:error];
    if (!data) {
        return nil;
    }

    NSError *unarchiveError = nil;
    id object = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSObject class] fromData:data error:&unarchiveError];
    if (!object) {
        if (error) {
            *error = unarchiveError ?: [NSError errorWithDomain:@"LKCLIReadCommand"
                                                           code:1
                                                       userInfo:@{NSLocalizedDescriptionKey: @"failed to decode .lookin file"}];
        }
        return nil;
    }

    NSError *verifyError = [LookinHierarchyFile verifyHierarchyFile:object];
    if (verifyError) {
        if (error) {
            *error = verifyError;
        }
        return nil;
    }
    return object;
}

+ (NSString *)absolutePathForPath:(NSString *)path {
    NSString *expandedPath = [path stringByExpandingTildeInPath];
    if (expandedPath.isAbsolutePath) {
        return expandedPath;
    }
    return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:expandedPath];
}

+ (LKCLIConnectedApp *)appForFile:(LookinHierarchyFile *)file {
    LKCLIConnectedApp *app = [LKCLIConnectedApp new];
    app.appInfo = file.hierarchyInfo.appInfo;
    return app;
}

+ (LKCLIExitCode)runSummaryWithFile:(LookinHierarchyFile *)file path:(NSString *)path arguments:(NSArray<NSString *> *)arguments {
    BOOL json = NO;
    for (NSString *argument in arguments) {
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        }
        if ([argument isEqualToString:@"--json"]) {
            json = YES;
            continue;
        }
        [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
        return LKCLIExitCodeUsage;
    }

    LookinHierarchyInfo *info = file.hierarchyInfo;
    NSArray<LookinDisplayItem *> *flatItems = [LookinDisplayItem flatItemsFromHierarchicalItems:info.displayItems ?: @[]];
    if (json) {
        NSDictionary *root = @{
            @"path": [self absolutePathForPath:path],
            @"serverVersion": @(file.serverVersion),
            @"itemCount": @(flatItems.count),
            @"app": @{
                @"name": info.appInfo.appName ?: [NSNull null],
                @"bundleIdentifier": info.appInfo.appBundleIdentifier ?: [NSNull null],
                @"device": info.appInfo.deviceDescription ?: [NSNull null],
                @"os": info.appInfo.osDescription ?: [NSNull null],
            },
        };
        return [LKCLIJSONWriter printJSONObject:root];
    }

    [LKCLIStdIO writeOut:@"%@ (%@)", info.appInfo.appName ?: @"<unknown>", info.appInfo.appBundleIdentifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"path: %@", [self absolutePathForPath:path]];
    [LKCLIStdIO writeOut:@"server version: %d", file.serverVersion];
    [LKCLIStdIO writeOut:@"items: %lu", (unsigned long)flatItems.count];
    return LKCLIExitCodeOK;
}

+ (LKCLIExitCode)runTreeWithFile:(LookinHierarchyFile *)file arguments:(NSArray<NSString *> *)arguments {
    BOOL json = NO;
    NSInteger depth = NSIntegerMax;
    NSString *filter = nil;
    unsigned long focusOID = 0;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([argument isEqualToString:@"--depth"]) {
            NSString *depthValue = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&depthValue errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            if (![LKCLITreeCommand parseDepthValue:depthValue depth:&depth]) {
                [LKCLIStdIO writeError:@"error: --depth must be a non-negative integer"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--filter"]) {
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&filter errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--oid"]) {
            NSString *oidValue = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&oidValue errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            if (![LKCLITreeCommand parseOIDValue:oidValue oid:&focusOID]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            return LKCLIExitCodeUsage;
        }
    }

    NSArray<LookinDisplayItem *> *displayItems = file.hierarchyInfo.displayItems ?: @[];
    if (focusOID != 0) {
        LookinDisplayItem *focusedItem = [LKCLITreeCommand firstItemInItems:displayItems matchingOID:focusOID];
        if (!focusedItem) {
            [LKCLIStdIO writeError:@"error: no display item found for oid %lu", focusOID];
            return LKCLIExitCodeObjectNotFound;
        }
        displayItems = @[focusedItem];
    }
    if (filter.length > 0) {
        displayItems = [LKCLITreeCommand filteredItemsFromItems:displayItems filter:filter];
    }

    LKCLIConnectedApp *app = [self appForFile:file];
    if (json) {
        return [LKCLITreeCommand printJSONWithItems:displayItems app:app depth:depth filter:filter focusOID:focusOID];
    }
    [LKCLITreeCommand printTextWithItems:displayItems app:app depth:depth filter:filter focusOID:focusOID];
    return LKCLIExitCodeOK;
}

+ (LKCLIExitCode)runFindWithFile:(LookinHierarchyFile *)file arguments:(NSArray<NSString *> *)arguments {
    BOOL json = NO;
    NSString *query = nil;
    unsigned long exactOID = 0;
    NSUInteger limit = 0;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([argument isEqualToString:@"--oid"]) {
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&query errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            if (![LKCLITreeCommand parseOIDValue:query oid:&exactOID]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--limit"]) {
            NSString *limitValue = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&limitValue errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            if (![LKCLITreeCommand parseLimitValue:limitValue limit:&limit]) {
                [LKCLIStdIO writeError:@"error: --limit must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument hasPrefix:@"-"]) {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            return LKCLIExitCodeUsage;
        } else if (query.length == 0) {
            query = argument;
        } else {
            [LKCLIStdIO writeError:@"error: unexpected argument '%@'", argument];
            return LKCLIExitCodeUsage;
        }
    }

    if (query.length == 0) {
        [LKCLIStdIO writeError:@"error: query is required"];
        return LKCLIExitCodeUsage;
    }

    NSArray<NSDictionary *> *matches = [LKCLITreeCommand matchesInItems:file.hierarchyInfo.displayItems ?: @[] query:query exactOID:exactOID limit:limit];
    LKCLIConnectedApp *app = [self appForFile:file];
    if (json) {
        return [LKCLITreeCommand printFindJSONWithMatches:matches app:app query:query limit:limit];
    }
    [LKCLITreeCommand printFindTextWithMatches:matches app:app query:query limit:limit];
    return LKCLIExitCodeOK;
}

+ (LKCLIExitCode)runInspectWithFile:(LookinHierarchyFile *)file arguments:(NSArray<NSString *> *)arguments {
    if ([LKCLIArgumentParser argumentsContainHelp:arguments]) {
        [self printHelp];
        return LKCLIExitCodeOK;
    }

    unsigned long oid = 0;
    BOOL json = NO;
    LKCLIExitCode parseExitCode = [self parseObjectArguments:arguments oid:&oid groupFilter:nil json:&json];
    if (parseExitCode != LKCLIExitCodeOK) {
        return parseExitCode;
    }

    LKCLIDisplayItemFetchResult *result = [self resultForFile:file oid:oid];
    if (!result) {
        [LKCLIStdIO writeError:@"error: no display item found for oid %lu", oid];
        return LKCLIExitCodeObjectNotFound;
    }

    if (json) {
        return [LKCLIInspectCommand printJSONWithResult:result];
    }
    [LKCLIInspectCommand printTextWithResult:result];
    return LKCLIExitCodeOK;
}

+ (LKCLIExitCode)runAttrsWithFile:(LookinHierarchyFile *)file arguments:(NSArray<NSString *> *)arguments {
    if ([LKCLIArgumentParser argumentsContainHelp:arguments]) {
        [self printHelp];
        return LKCLIExitCodeOK;
    }

    unsigned long oid = 0;
    BOOL json = NO;
    NSString *groupFilter = nil;
    LKCLIExitCode parseExitCode = [self parseObjectArguments:arguments oid:&oid groupFilter:&groupFilter json:&json];
    if (parseExitCode != LKCLIExitCodeOK) {
        return parseExitCode;
    }

    LKCLIDisplayItemFetchResult *result = [self resultForFile:file oid:oid];
    if (!result) {
        [LKCLIStdIO writeError:@"error: no display item found for oid %lu", oid];
        return LKCLIExitCodeObjectNotFound;
    }

    if (json) {
        return [LKCLIAttrsCommand printJSONWithResult:result groupFilter:groupFilter];
    }
    [LKCLIAttrsCommand printTextWithResult:result groupFilter:groupFilter];
    return LKCLIExitCodeOK;
}

+ (LKCLIExitCode)parseObjectArguments:(NSArray<NSString *> *)arguments oid:(unsigned long *)oid groupFilter:(NSString **)groupFilter json:(BOOL *)json {
    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
            [self printHelp];
            return LKCLIExitCodeUsage;
        } else if ([argument isEqualToString:@"--json"]) {
            if (json) {
                *json = YES;
            }
        } else if ([argument isEqualToString:@"--oid"]) {
            NSString *oidValue = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&oidValue errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            if (![LKCLIDisplayItemFetcher parseOIDValue:oidValue oid:oid]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--group"] && groupFilter) {
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:groupFilter errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            return LKCLIExitCodeUsage;
        }
    }

    if (oid && *oid == 0) {
        [LKCLIStdIO writeError:@"error: --oid is required"];
        return LKCLIExitCodeUsage;
    }
    return LKCLIExitCodeOK;
}

+ (LKCLIDisplayItemFetchResult *)resultForFile:(LookinHierarchyFile *)file oid:(unsigned long)oid {
    LookinDisplayItem *item = [LKCLITreeCommand firstItemInItems:file.hierarchyInfo.displayItems ?: @[] matchingOID:oid];
    if (!item) {
        return nil;
    }

    LKCLIDisplayItemFetchResult *result = [LKCLIDisplayItemFetchResult new];
    result.app = [self appForFile:file];
    result.hierarchyInfo = file.hierarchyInfo;
    result.displayItem = item;
    result.object = [self preferredObjectForDisplayItem:item requestedOID:oid];
    result.attributeGroups = [item queryAllAttrGroupList] ?: @[];
    result.requestedOID = oid;
    result.detailOID = item.layerObject.oid ?: result.object.oid;
    return result;
}

+ (LookinObject *)preferredObjectForDisplayItem:(LookinDisplayItem *)item requestedOID:(unsigned long)oid {
    if (item.viewObject.oid == oid) {
        return item.viewObject;
    }
    if (item.layerObject.oid == oid) {
        return item.layerObject;
    }
    if (item.hostViewControllerObject.oid == oid) {
        return item.hostViewControllerObject;
    }
    if (item.displayingObject.oid == oid) {
        return item.displayingObject;
    }
    return item.displayingObject ?: item.layerObject ?: item.hostViewControllerObject;
}

@end
