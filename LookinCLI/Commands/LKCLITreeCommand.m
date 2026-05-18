#import "LKCLITreeCommand.h"
#import "LKCLIAppScanner.h"
#import "LKCLIAppSelector.h"
#import "LKCLIConnectedApp.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LookinAppInfo.h"
#import "LookinHierarchyInfo.h"
#import "LookinDisplayItem.h"
#import "LookinObject.h"

@implementation LKCLITreeCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    BOOL json = NO;
    NSInteger depth = NSIntegerMax;
    NSString *filter = nil;
    unsigned long focusOID = 0;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
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
        } else if ([argument isEqualToString:@"--depth"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --depth requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *depthValue = arguments[++idx];
            NSInteger parsedDepth = 0;
            if (![self parseDepthValue:depthValue depth:&parsedDepth]) {
                [LKCLIStdIO writeError:@"error: --depth must be a non-negative integer"];
                return LKCLIExitCodeUsage;
            }
            depth = parsedDepth;
        } else if ([argument isEqualToString:@"--filter"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --filter requires a value"];
                return LKCLIExitCodeUsage;
            }
            filter = arguments[++idx];
        } else if ([argument isEqualToString:@"--oid"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --oid requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *oidValue = arguments[++idx];
            if (![self parseOIDValue:oidValue oid:&focusOID]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin tree --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }

    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    id appsValue = nil;
    NSError *appsError = nil;
    BOOL fetchedApps = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:8 value:&appsValue error:&appsError];
    if (!fetchedApps) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: %@", appsError.localizedDescription ?: @"failed to fetch apps"];
        return LKCLIExitCodeConnection;
    }

    LKCLIExitCode selectionExitCode = LKCLIExitCodeOK;
    LKCLIConnectedApp *app = [[LKCLIAppSelector new] selectAppFromAppsValue:appsValue selection:selection exitCode:&selectionExitCode];
    if (!app) {
        [scanner closeAllConnections];
        return selectionExitCode;
    }

    id hierarchyValue = nil;
    NSError *hierarchyError = nil;
    BOOL fetchedHierarchy = [LKCLISignalRunner waitForSignal:[scanner fetchHierarchyForApp:app] timeout:12 value:&hierarchyValue error:&hierarchyError];
    [scanner closeAllConnections];

    if (!fetchedHierarchy) {
        [LKCLIStdIO writeError:@"error: %@", hierarchyError.localizedDescription ?: @"failed to fetch hierarchy"];
        return LKCLIExitCodeConnection;
    }
    if (![hierarchyValue isKindOfClass:[LookinHierarchyInfo class]]) {
        [LKCLIStdIO writeError:@"error: invalid hierarchy response"];
        return LKCLIExitCodeGeneralError;
    }

    LookinHierarchyInfo *hierarchyInfo = hierarchyValue;
    NSArray<LookinDisplayItem *> *displayItems = hierarchyInfo.displayItems ?: @[];
    if (focusOID != 0) {
        LookinDisplayItem *focusedItem = [self firstItemInItems:displayItems matchingOID:focusOID];
        if (!focusedItem) {
            [LKCLIStdIO writeError:@"error: no display item found for oid %lu", focusOID];
            return LKCLIExitCodeGeneralError;
        }
        displayItems = @[focusedItem];
    }
    if (filter.length > 0) {
        displayItems = [self filteredItemsFromItems:displayItems filter:filter];
    }

    if (json) {
        return [self printJSONWithItems:displayItems app:app depth:depth filter:filter focusOID:focusOID];
    }
    [self printTextWithItems:displayItems app:app depth:depth filter:filter focusOID:focusOID];
    return LKCLIExitCodeOK;
}

+ (LKCLIExitCode)runFindWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    BOOL json = NO;
    NSString *query = nil;
    unsigned long exactOID = 0;
    NSUInteger limit = 0;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            [self printFindHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([LKCLIAppSelector isSelectionArgument:argument]) {
            NSString *errorMessage = nil;
            if (![LKCLIAppSelector consumeSelectionArgument:argument arguments:arguments index:&idx selection:selection errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage ?: @"error: invalid app selector option"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--filter"] || [argument isEqualToString:@"--query"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: %@ requires a value", argument];
                return LKCLIExitCodeUsage;
            }
            query = arguments[++idx];
        } else if ([argument isEqualToString:@"--oid"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --oid requires a value"];
                return LKCLIExitCodeUsage;
            }
            query = arguments[++idx];
            unsigned long unusedOID = 0;
            if (![self parseOIDValue:query oid:&unusedOID]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
            exactOID = unusedOID;
        } else if ([argument isEqualToString:@"--limit"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --limit requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSUInteger parsedLimit = 0;
            if (![self parseLimitValue:arguments[++idx] limit:&parsedLimit]) {
                [LKCLIStdIO writeError:@"error: --limit must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
            limit = parsedLimit;
        } else if ([argument hasPrefix:@"-"]) {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin find --help'"];
            return LKCLIExitCodeUsage;
        } else if (query.length == 0) {
            query = argument;
        } else {
            [LKCLIStdIO writeError:@"error: unexpected argument '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin find --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (query.length == 0) {
        [LKCLIStdIO writeError:@"error: query is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin find --bundle-id %@ UILabel'", selection.bundleID];
        return LKCLIExitCodeUsage;
    }

    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    id appsValue = nil;
    NSError *appsError = nil;
    BOOL fetchedApps = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:8 value:&appsValue error:&appsError];
    if (!fetchedApps) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: %@", appsError.localizedDescription ?: @"failed to fetch apps"];
        return LKCLIExitCodeConnection;
    }

    LKCLIExitCode selectionExitCode = LKCLIExitCodeOK;
    LKCLIConnectedApp *app = [[LKCLIAppSelector new] selectAppFromAppsValue:appsValue selection:selection exitCode:&selectionExitCode];
    if (!app) {
        [scanner closeAllConnections];
        return selectionExitCode;
    }

    id hierarchyValue = nil;
    NSError *hierarchyError = nil;
    BOOL fetchedHierarchy = [LKCLISignalRunner waitForSignal:[scanner fetchHierarchyForApp:app] timeout:12 value:&hierarchyValue error:&hierarchyError];
    [scanner closeAllConnections];

    if (!fetchedHierarchy) {
        [LKCLIStdIO writeError:@"error: %@", hierarchyError.localizedDescription ?: @"failed to fetch hierarchy"];
        return LKCLIExitCodeConnection;
    }
    if (![hierarchyValue isKindOfClass:[LookinHierarchyInfo class]]) {
        [LKCLIStdIO writeError:@"error: invalid hierarchy response"];
        return LKCLIExitCodeGeneralError;
    }

    NSArray<NSDictionary *> *matches = [self matchesInItems:((LookinHierarchyInfo *)hierarchyValue).displayItems query:query exactOID:exactOID limit:limit];
    if (json) {
        return [self printFindJSONWithMatches:matches app:app query:query limit:limit];
    }
    [self printFindTextWithMatches:matches app:app query:query limit:limit];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin tree --bundle-id <bundle-id> [--json] [--depth N] [--filter <text>] [--oid <oid>] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Fetch and print the UI hierarchy for a reachable iOS app.\n"
      "\n"
      "Options:\n"
      "  --filter <text>  Keep matching nodes and their ancestors.\n"
      "  --oid <oid>      Print the subtree rooted at the matching view/layer/controller oid."];
}

+ (void)printFindHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin find --bundle-id <bundle-id> <query> [--json] [--limit N] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  lookin find --bundle-id <bundle-id> --oid <oid> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Find hierarchy nodes by class name, custom title, memory address, or object id."];
}

+ (BOOL)parseDepthValue:(NSString *)value depth:(NSInteger *)depth {
    if (value.length == 0) {
        return NO;
    }

    NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    NSCharacterSet *nonDigits = [digits invertedSet];
    if ([value rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return NO;
    }

    NSString *normalizedValue = value;
    while (normalizedValue.length > 1 && [normalizedValue hasPrefix:@"0"]) {
        normalizedValue = [normalizedValue substringFromIndex:1];
    }

    NSString *maxValue = [NSString stringWithFormat:@"%ld", (long)NSIntegerMax];
    if (normalizedValue.length > maxValue.length ||
        (normalizedValue.length == maxValue.length && [normalizedValue compare:maxValue] == NSOrderedDescending)) {
        return NO;
    }
    if (depth) {
        *depth = value.integerValue;
    }
    return YES;
}

+ (BOOL)parseOIDValue:(NSString *)value oid:(unsigned long *)oid {
    if (value.length == 0) {
        return NO;
    }

    NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    if ([value rangeOfCharacterFromSet:digits.invertedSet].location != NSNotFound) {
        return NO;
    }

    unsigned long parsedValue = strtoul(value.UTF8String, NULL, 10);
    if (parsedValue == 0) {
        return NO;
    }
    if (oid) {
        *oid = parsedValue;
    }
    return YES;
}

+ (BOOL)parseLimitValue:(NSString *)value limit:(NSUInteger *)limit {
    unsigned long parsedValue = 0;
    if (![self parseOIDValue:value oid:&parsedValue]) {
        return NO;
    }
    if (limit) {
        *limit = (NSUInteger)parsedValue;
    }
    return YES;
}

+ (void)printTextWithItems:(NSArray<LookinDisplayItem *> *)items app:(LKCLIConnectedApp *)app depth:(NSInteger)depth filter:(NSString *)filter focusOID:(unsigned long)focusOID {
    LookinAppInfo *info = app.appInfo;
    [LKCLIStdIO writeOut:@"%@ (%@)", info.appName ?: @"<unknown>", info.appBundleIdentifier ?: @"<unknown>"];
    if (focusOID != 0) {
        [LKCLIStdIO writeOut:@"focused oid: %lu", focusOID];
    }
    if (filter.length > 0) {
        [LKCLIStdIO writeOut:@"filter: %@", filter];
    }

    if (items.count == 0) {
        [LKCLIStdIO writeOut:@"<no matching items>"];
        return;
    }
    for (LookinDisplayItem *item in items) {
        [self printTextItem:item level:0 depth:depth];
    }
}

+ (void)printTextItem:(LookinDisplayItem *)item level:(NSInteger)level depth:(NSInteger)depth {
    if (level > depth) {
        return;
    }

    NSMutableString *indent = [NSMutableString string];
    for (NSInteger idx = 0; idx < level; idx++) {
        [indent appendString:@"  "];
    }

    LookinObject *object = item.displayingObject;
    NSString *className = object.rawClassName ?: @"<unknown>";
    NSString *title = item.customDisplayTitle.length ? [NSString stringWithFormat:@" %@", item.customDisplayTitle] : @"";
    NSString *objectIDs = [self secondaryObjectIDsTextForItem:item primaryObject:object];
    CGRect frame = item.frame;
    NSString *flags = [self flagsForItem:item];

    [LKCLIStdIO writeOut:@"%@- %@%@ oid=%lu%@ frame=(%.1f, %.1f, %.1f, %.1f)%@",
     indent,
     className,
     title,
     object.oid,
     objectIDs,
     frame.origin.x,
     frame.origin.y,
     frame.size.width,
     frame.size.height,
     flags];

    if (level == depth) {
        return;
    }
    for (LookinDisplayItem *subitem in item.subitems) {
        [self printTextItem:subitem level:level + 1 depth:depth];
    }
}

+ (NSString *)secondaryObjectIDsTextForItem:(LookinDisplayItem *)item primaryObject:(LookinObject *)primaryObject {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    if (item.viewObject && item.viewObject != primaryObject) {
        [ids addObject:[NSString stringWithFormat:@"viewOid=%lu", item.viewObject.oid]];
    }
    if (item.layerObject && item.layerObject != primaryObject) {
        [ids addObject:[NSString stringWithFormat:@"layerOid=%lu", item.layerObject.oid]];
    }
    if (item.hostViewControllerObject && item.hostViewControllerObject != primaryObject) {
        [ids addObject:[NSString stringWithFormat:@"controllerOid=%lu", item.hostViewControllerObject.oid]];
    }
    if (ids.count == 0) {
        return @"";
    }
    return [NSString stringWithFormat:@" %@", [ids componentsJoinedByString:@" "]];
}

+ (NSString *)flagsForItem:(LookinDisplayItem *)item {
    NSMutableArray<NSString *> *flags = [NSMutableArray array];
    if (item.representedAsKeyWindow) {
        [flags addObject:@"keyWindow"];
    }
    if (item.isHidden) {
        [flags addObject:@"hidden"];
    }
    if (item.alpha < 1) {
        [flags addObject:[NSString stringWithFormat:@"alpha=%.2f", item.alpha]];
    }
    if (flags.count == 0) {
        return @"";
    }
    return [NSString stringWithFormat:@" [%@]", [flags componentsJoinedByString:@", "]];
}

+ (LKCLIExitCode)printJSONWithItems:(NSArray<LookinDisplayItem *> *)displayItems app:(LKCLIConnectedApp *)app depth:(NSInteger)depth filter:(NSString *)filter focusOID:(unsigned long)focusOID {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithCapacity:displayItems.count];
    for (LookinDisplayItem *item in displayItems) {
        [items addObject:[self JSONObjectForItem:item level:0 depth:depth]];
    }

    NSDictionary *root = @{
        @"app": @{
            @"name": app.appInfo.appName ?: [NSNull null],
            @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
            @"device": app.appInfo.deviceDescription ?: [NSNull null],
            @"os": app.appInfo.osDescription ?: [NSNull null],
        },
        @"filter": filter ?: [NSNull null],
        @"focusOid": focusOID == 0 ? [NSNull null] : @(focusOID),
        @"items": items,
    };

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data) {
        [LKCLIStdIO writeError:@"error: %@", error.localizedDescription ?: @"failed to encode JSON"];
        return LKCLIExitCodeGeneralError;
    }
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [LKCLIStdIO writeOut:@"%@", jsonString];
    return LKCLIExitCodeOK;
}

+ (NSDictionary *)JSONObjectForItem:(LookinDisplayItem *)item level:(NSInteger)level depth:(NSInteger)depth {
    LookinObject *object = item.displayingObject;
    CGRect frame = item.frame;

    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    json[@"oid"] = @(object.oid);
    json[@"viewOid"] = item.viewObject ? @(item.viewObject.oid) : [NSNull null];
    json[@"layerOid"] = item.layerObject ? @(item.layerObject.oid) : [NSNull null];
    json[@"hostViewControllerOid"] = item.hostViewControllerObject ? @(item.hostViewControllerObject.oid) : [NSNull null];
    json[@"className"] = object.rawClassName ?: [NSNull null];
    json[@"customTitle"] = item.customDisplayTitle ?: [NSNull null];
    json[@"hidden"] = @(item.isHidden);
    json[@"alpha"] = @(item.alpha);
    json[@"keyWindow"] = @(item.representedAsKeyWindow);
    json[@"frame"] = @{
        @"x": @(frame.origin.x),
        @"y": @(frame.origin.y),
        @"width": @(frame.size.width),
        @"height": @(frame.size.height),
    };

    NSMutableArray<NSDictionary *> *children = [NSMutableArray array];
    if (level < depth) {
        for (LookinDisplayItem *subitem in item.subitems) {
            [children addObject:[self JSONObjectForItem:subitem level:level + 1 depth:depth]];
        }
    }
    json[@"children"] = children;
    return json.copy;
}

+ (NSArray<LookinDisplayItem *> *)filteredItemsFromItems:(NSArray<LookinDisplayItem *> *)items filter:(NSString *)filter {
    NSMutableArray<LookinDisplayItem *> *filteredItems = [NSMutableArray array];
    for (LookinDisplayItem *item in items) {
        LookinDisplayItem *filteredItem = [self filteredItemFromItem:item filter:filter];
        if (filteredItem) {
            [filteredItems addObject:filteredItem];
        }
    }
    return filteredItems.copy;
}

+ (LookinDisplayItem *)filteredItemFromItem:(LookinDisplayItem *)item filter:(NSString *)filter {
    NSMutableArray<LookinDisplayItem *> *filteredSubitems = [NSMutableArray array];
    for (LookinDisplayItem *subitem in item.subitems) {
        LookinDisplayItem *filteredSubitem = [self filteredItemFromItem:subitem filter:filter];
        if (filteredSubitem) {
            [filteredSubitems addObject:filteredSubitem];
        }
    }

    if (![self item:item matchesQuery:filter] && filteredSubitems.count == 0) {
        return nil;
    }

    LookinDisplayItem *copiedItem = [item copy];
    copiedItem.subitems = filteredSubitems;
    return copiedItem;
}

+ (LookinDisplayItem *)firstItemInItems:(NSArray<LookinDisplayItem *> *)items matchingOID:(unsigned long)oid {
    for (LookinDisplayItem *item in items) {
        if ([self item:item matchesOID:oid]) {
            return item;
        }
        LookinDisplayItem *matchedSubitem = [self firstItemInItems:item.subitems matchingOID:oid];
        if (matchedSubitem) {
            return matchedSubitem;
        }
    }
    return nil;
}

+ (BOOL)item:(LookinDisplayItem *)item matchesOID:(unsigned long)oid {
    return item.displayingObject.oid == oid ||
           item.viewObject.oid == oid ||
           item.layerObject.oid == oid ||
           item.hostViewControllerObject.oid == oid;
}

+ (BOOL)item:(LookinDisplayItem *)item matchesQuery:(NSString *)query {
    if (query.length == 0) {
        return YES;
    }

    unsigned long oid = 0;
    BOOL queryIsOID = [self parseOIDValue:query oid:&oid];
    if (queryIsOID && [self item:item matchesOID:oid]) {
        return YES;
    }

    for (NSString *candidate in [self searchableStringsForItem:item]) {
        if ([candidate rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

+ (NSArray<NSString *> *)searchableStringsForItem:(LookinDisplayItem *)item {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (LookinObject *object in @[item.displayingObject ?: (LookinObject *)[NSNull null],
                                   item.viewObject ?: (LookinObject *)[NSNull null],
                                   item.layerObject ?: (LookinObject *)[NSNull null],
                                   item.hostViewControllerObject ?: (LookinObject *)[NSNull null]]) {
        if (![object isKindOfClass:[LookinObject class]]) {
            continue;
        }
        if (object.rawClassName.length) {
            [strings addObject:object.rawClassName];
        }
        if (object.memoryAddress.length) {
            [strings addObject:object.memoryAddress];
        }
        if (object.oid != 0) {
            [strings addObject:[NSString stringWithFormat:@"%lu", object.oid]];
        }
    }
    if (item.customDisplayTitle.length) {
        [strings addObject:item.customDisplayTitle];
    }
    return strings.copy;
}

+ (NSArray<NSDictionary *> *)matchesInItems:(NSArray<LookinDisplayItem *> *)items query:(NSString *)query exactOID:(unsigned long)exactOID limit:(NSUInteger)limit {
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    [self collectMatchesInItems:items query:query exactOID:exactOID path:@[] depth:0 limit:limit matches:matches];
    return matches.copy;
}

+ (void)collectMatchesInItems:(NSArray<LookinDisplayItem *> *)items
                        query:(NSString *)query
                     exactOID:(unsigned long)exactOID
                         path:(NSArray<NSString *> *)path
                        depth:(NSUInteger)depth
                        limit:(NSUInteger)limit
                      matches:(NSMutableArray<NSDictionary *> *)matches {
    if (limit != 0 && matches.count >= limit) {
        return;
    }

    for (LookinDisplayItem *item in items) {
        NSString *name = item.displayingObject.rawClassName ?: @"<unknown>";
        NSArray<NSString *> *itemPath = [path arrayByAddingObject:name];
        BOOL matched = exactOID != 0 ? [self item:item matchesOID:exactOID] : [self item:item matchesQuery:query];
        if (matched) {
            NSMutableDictionary *match = [[self JSONObjectForItem:item level:0 depth:0] mutableCopy];
            match[@"depth"] = @(depth);
            match[@"path"] = itemPath;
            match[@"pathString"] = [itemPath componentsJoinedByString:@" > "];
            [matches addObject:match.copy];
            if (limit != 0 && matches.count >= limit) {
                return;
            }
        }
        [self collectMatchesInItems:item.subitems query:query exactOID:exactOID path:itemPath depth:depth + 1 limit:limit matches:matches];
        if (limit != 0 && matches.count >= limit) {
            return;
        }
    }
}

+ (void)printFindTextWithMatches:(NSArray<NSDictionary *> *)matches app:(LKCLIConnectedApp *)app query:(NSString *)query limit:(NSUInteger)limit {
    LookinAppInfo *info = app.appInfo;
    [LKCLIStdIO writeOut:@"%@ (%@)", info.appName ?: @"<unknown>", info.appBundleIdentifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"query: %@", query];
    if (limit != 0) {
        [LKCLIStdIO writeOut:@"limit: %lu", (unsigned long)limit];
    }
    [LKCLIStdIO writeOut:@"matches: %lu", (unsigned long)matches.count];
    if (matches.count == 0) {
        return;
    }

    for (NSDictionary *match in matches) {
        NSDictionary *frame = match[@"frame"];
        [LKCLIStdIO writeOut:@"- oid=%@ class=%@ frame=(%.1f, %.1f, %.1f, %.1f)%@",
         match[@"oid"],
         match[@"className"] ?: @"<unknown>",
         [frame[@"x"] doubleValue],
         [frame[@"y"] doubleValue],
         [frame[@"width"] doubleValue],
         [frame[@"height"] doubleValue],
         [match[@"hidden"] boolValue] ? @" [hidden]" : @""];
        [LKCLIStdIO writeOut:@"  path: %@", match[@"pathString"] ?: @""];
    }
}

+ (LKCLIExitCode)printFindJSONWithMatches:(NSArray<NSDictionary *> *)matches app:(LKCLIConnectedApp *)app query:(NSString *)query limit:(NSUInteger)limit {
    NSDictionary *root = @{
        @"app": @{
            @"name": app.appInfo.appName ?: [NSNull null],
            @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
            @"device": app.appInfo.deviceDescription ?: [NSNull null],
            @"os": app.appInfo.osDescription ?: [NSNull null],
        },
        @"query": query ?: [NSNull null],
        @"limit": limit == 0 ? [NSNull null] : @(limit),
        @"count": @(matches.count),
        @"matches": matches,
    };

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data) {
        [LKCLIStdIO writeError:@"error: %@", error.localizedDescription ?: @"failed to encode JSON"];
        return LKCLIExitCodeGeneralError;
    }
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [LKCLIStdIO writeOut:@"%@", jsonString];
    return LKCLIExitCodeOK;
}

@end
