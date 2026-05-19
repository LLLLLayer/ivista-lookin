#import "LKCLITreeCommand.h"
#import "LKCLIArgumentParser.h"
#import "LKCLIAppSelector.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIJSONWriter.h"
#import "LKCLIOnlineCommandRunner.h"
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
        } else if ([argument isEqualToString:@"--depth"]) {
            NSString *depthValue = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&depthValue errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            NSInteger parsedDepth = 0;
            if (![self parseDepthValue:depthValue depth:&parsedDepth]) {
                [LKCLIStdIO writeError:@"error: --depth must be a non-negative integer"];
                return LKCLIExitCodeUsage;
            }
            depth = parsedDepth;
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
            if (![self parseOIDValue:oidValue oid:&focusOID]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'ivista-lookin tree --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }

    return [LKCLIOnlineCommandRunner withHierarchyForSelection:selection appsTimeout:8 hierarchyTimeout:12 body:^LKCLIExitCode(LKCLIAppScanner *scanner, LKCLIConnectedApp *app, LookinHierarchyInfo *hierarchyInfo) {
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
    }];
}

+ (LKCLIExitCode)runFindWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    BOOL json = NO;
    NSString *query = nil;
    unsigned long exactOID = 0;
    NSUInteger limit = 0;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([LKCLIArgumentParser isHelpArgument:argument]) {
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
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&query errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--oid"]) {
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&query errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            unsigned long unusedOID = 0;
            if (![self parseOIDValue:query oid:&unusedOID]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
            exactOID = unusedOID;
        } else if ([argument isEqualToString:@"--limit"]) {
            NSString *limitValue = nil;
            NSString *errorMessage = nil;
            if (![LKCLIArgumentParser consumeValueForOption:argument arguments:arguments index:&idx value:&limitValue errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage];
                return LKCLIExitCodeUsage;
            }
            NSUInteger parsedLimit = 0;
            if (![self parseLimitValue:limitValue limit:&parsedLimit]) {
                [LKCLIStdIO writeError:@"error: --limit must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
            limit = parsedLimit;
        } else if ([argument hasPrefix:@"-"]) {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'ivista-lookin find --help'"];
            return LKCLIExitCodeUsage;
        } else if (query.length == 0) {
            query = argument;
        } else {
            [LKCLIStdIO writeError:@"error: unexpected argument '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'ivista-lookin find --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (query.length == 0) {
        [LKCLIStdIO writeError:@"error: query is required"];
        [LKCLIStdIO writeError:@"hint: run 'ivista-lookin find --bundle-id %@ UILabel'", selection.bundleID];
        return LKCLIExitCodeUsage;
    }

    return [LKCLIOnlineCommandRunner withHierarchyForSelection:selection appsTimeout:8 hierarchyTimeout:12 body:^LKCLIExitCode(LKCLIAppScanner *scanner, LKCLIConnectedApp *app, LookinHierarchyInfo *hierarchyInfo) {
        NSArray<NSDictionary *> *matches = [self matchesInItems:hierarchyInfo.displayItems query:query exactOID:exactOID limit:limit];
        if (json) {
            return [self printFindJSONWithMatches:matches app:app query:query limit:limit];
        }
        [self printFindTextWithMatches:matches app:app query:query limit:limit];
        return LKCLIExitCodeOK;
    }];
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  ivista-lookin tree --bundle-id <bundle-id> [--json] [--depth N] [--filter <text>] [--oid <oid>] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
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
      "  ivista-lookin find --bundle-id <bundle-id> <query> [--json] [--limit N] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "  ivista-lookin find --bundle-id <bundle-id> --oid <oid> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Find hierarchy nodes by class name, custom title, memory address, or object id."];
}

+ (BOOL)parseDepthValue:(NSString *)value depth:(NSInteger *)depth {
    return [LKCLIArgumentParser parseIntegerValue:value min:0 max:NSIntegerMax result:depth];
}

+ (BOOL)parseOIDValue:(NSString *)value oid:(unsigned long *)oid {
    return [LKCLIArgumentParser parsePositiveOIDValue:value oid:oid];
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

    return [LKCLIJSONWriter printJSONObject:root];
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

    return [LKCLIJSONWriter printJSONObject:root];
}

@end
