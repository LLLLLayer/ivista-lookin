#import "LKCLIInspectCommand.h"
#import "LKCLIAppScanner.h"
#import "LKCLIConnectedApp.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LKCLIVersionProvider.h"
#import "LookinAppInfo.h"
#import "LookinAttribute.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import "LookinDisplayItem.h"
#import "LookinDisplayItemDetail.h"
#import "LookinHierarchyInfo.h"
#import "LookinObject.h"
#import "LookinStaticAsyncUpdateTask.h"
#import <AppKit/AppKit.h>
#import <limits.h>
#import <stdlib.h>

@implementation LKCLIInspectCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    NSString *bundleID = nil;
    unsigned long oid = 0;
    BOOL json = NO;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([argument isEqualToString:@"--bundle-id"] || [argument isEqualToString:@"-b"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: %@ requires a value", argument];
                return LKCLIExitCodeUsage;
            }
            bundleID = arguments[++idx];
        } else if ([argument isEqualToString:@"--oid"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --oid requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *oidValue = arguments[++idx];
            if (![self parseOIDValue:oidValue oid:&oid]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin inspect --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (oid == 0) {
        [LKCLIStdIO writeError:@"error: --oid is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin tree --bundle-id %@' to find object ids", bundleID];
        return LKCLIExitCodeUsage;
    }

    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    id appsValue = nil;
    NSError *appsError = nil;
    BOOL fetchedApps = [LKCLISignalRunner waitForSignal:[scanner fetchAppsWithImages:NO] timeout:10 value:&appsValue error:&appsError];
    if (!fetchedApps) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: %@", appsError.localizedDescription ?: @"failed to fetch apps"];
        return LKCLIExitCodeConnection;
    }

    NSArray<LKCLIConnectedApp *> *matchingApps = [self appsMatchingBundleID:bundleID inApps:appsValue];
    if (matchingApps.count == 0) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: no inspectable app found for bundle id '%@'", bundleID];
        return LKCLIExitCodeNoApp;
    }
    if (matchingApps.count > 1) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: multiple apps matched bundle id '%@'", bundleID];
        [LKCLIStdIO writeError:@"hint: device selection will be added in a later command revision"];
        return LKCLIExitCodeAmbiguousApp;
    }

    LKCLIConnectedApp *app = matchingApps.firstObject;
    id hierarchyValue = nil;
    NSError *hierarchyError = nil;
    BOOL fetchedHierarchy = [LKCLISignalRunner waitForSignal:[scanner fetchHierarchyForApp:app] timeout:12 value:&hierarchyValue error:&hierarchyError];
    if (!fetchedHierarchy) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: %@", hierarchyError.localizedDescription ?: @"failed to fetch hierarchy"];
        return LKCLIExitCodeConnection;
    }
    if (![hierarchyValue isKindOfClass:[LookinHierarchyInfo class]]) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: invalid hierarchy response"];
        return LKCLIExitCodeGeneralError;
    }

    LookinHierarchyInfo *hierarchyInfo = hierarchyValue;
    LookinDisplayItem *displayItem = [self displayItemMatchingOID:oid inItems:hierarchyInfo.displayItems];
    if (!displayItem) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: no display item found for oid %lu", oid];
        return LKCLIExitCodeObjectNotFound;
    }

    LookinObject *object = [self preferredObjectForDisplayItem:displayItem requestedOID:oid];
    unsigned long detailOID = displayItem.layerObject.oid ?: object.oid;
    if (detailOID == 0) {
        [scanner closeAllConnections];
        [LKCLIStdIO writeError:@"error: display item has no inspectable object for oid %lu", oid];
        return LKCLIExitCodeObjectNotFound;
    }
    NSArray *packages = [self detailPackagesForDisplayItem:displayItem detailOID:detailOID];
    id detailsValue = nil;
    NSError *detailsError = nil;
    BOOL fetchedDetails = [LKCLISignalRunner waitForSignal:[scanner fetchHierarchyDetailsWithTaskPackages:packages forApp:app] timeout:12 value:&detailsValue error:&detailsError];
    [scanner closeAllConnections];

    if (!fetchedDetails) {
        [LKCLIStdIO writeError:@"error: %@", detailsError.localizedDescription ?: @"failed to fetch display item details"];
        return LKCLIExitCodeConnection;
    }

    NSArray<LookinAttributesGroup *> *groups = [self attributeGroupsFromDetailsValue:detailsValue detailOID:detailOID fallbackItem:displayItem];
    if (json) {
        return [self printJSONWithObject:object displayItem:displayItem groups:groups app:app];
    }
    [self printTextWithObject:object displayItem:displayItem groups:groups app:app];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin inspect --bundle-id <bundle-id> --oid <oid> [--json]\n"
      "\n"
      "Fetch object metadata and dashboard attributes for a reachable iOS app."];
}

+ (NSArray<LKCLIConnectedApp *> *)appsMatchingBundleID:(NSString *)bundleID inApps:(id)appsValue {
    if (![appsValue isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<LKCLIConnectedApp *> *matches = [NSMutableArray array];
    for (LKCLIConnectedApp *app in (NSArray *)appsValue) {
        if (![app isKindOfClass:[LKCLIConnectedApp class]] || app.serverVersionError) {
            continue;
        }
        if ([app.appInfo.appBundleIdentifier isEqualToString:bundleID]) {
            [matches addObject:app];
        }
    }
    return matches.copy;
}

+ (BOOL)parseOIDValue:(NSString *)value oid:(unsigned long *)oid {
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
    if ([normalizedValue isEqualToString:@"0"]) {
        return NO;
    }

    NSString *maxValue = [NSString stringWithFormat:@"%lu", ULONG_MAX];
    if (normalizedValue.length > maxValue.length ||
        (normalizedValue.length == maxValue.length && [normalizedValue compare:maxValue] == NSOrderedDescending)) {
        return NO;
    }
    if (oid) {
        *oid = strtoul(value.UTF8String, NULL, 10);
    }
    return YES;
}

+ (LookinDisplayItem *)displayItemMatchingOID:(unsigned long)oid inItems:(NSArray<LookinDisplayItem *> *)items {
    for (LookinDisplayItem *item in items) {
        if (item.viewObject.oid == oid || item.layerObject.oid == oid || item.hostViewControllerObject.oid == oid) {
            return item;
        }
        LookinDisplayItem *matchedSubitem = [self displayItemMatchingOID:oid inItems:item.subitems];
        if (matchedSubitem) {
            return matchedSubitem;
        }
    }
    return nil;
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
    return item.displayingObject ?: item.layerObject ?: item.hostViewControllerObject;
}

+ (NSArray *)detailPackagesForDisplayItem:(LookinDisplayItem *)item detailOID:(unsigned long)detailOID {
    LookinStaticAsyncUpdateTask *task = [LookinStaticAsyncUpdateTask new];
    task.oid = detailOID;
    task.taskType = LookinStaticAsyncUpdateTaskTypeNoScreenshot;
    task.attrRequest = LookinDetailUpdateTaskAttrRequest_Need;
    task.needBasisVisualInfo = YES;
    task.frameSize = item.frame.size;
    task.clientReadableVersion = [LKCLIVersionProvider cliVersion];

    LookinStaticAsyncUpdateTasksPackage *package = [LookinStaticAsyncUpdateTasksPackage new];
    package.tasks = @[task];
    return @[package];
}

+ (NSArray<LookinAttributesGroup *> *)attributeGroupsFromDetailsValue:(id)detailsValue detailOID:(unsigned long)detailOID fallbackItem:(LookinDisplayItem *)fallbackItem {
    NSMutableArray<LookinAttributesGroup *> *groups = [NSMutableArray array];
    if ([detailsValue isKindOfClass:[NSArray class]]) {
        for (LookinDisplayItemDetail *detail in (NSArray *)detailsValue) {
            if (![detail isKindOfClass:[LookinDisplayItemDetail class]] || detail.failureCode == -1) {
                continue;
            }
            if (detail.displayItemOid != 0 && detail.displayItemOid != detailOID) {
                continue;
            }
            [groups addObjectsFromArray:detail.attributesGroupList ?: @[]];
            [groups addObjectsFromArray:detail.customAttrGroupList ?: @[]];
            if (groups.count > 0) {
                return groups.copy;
            }
        }
    }

    [groups addObjectsFromArray:fallbackItem.attributesGroupList ?: @[]];
    [groups addObjectsFromArray:fallbackItem.customAttrGroupList ?: @[]];
    return groups.copy;
}

+ (void)printTextWithObject:(LookinObject *)object displayItem:(LookinDisplayItem *)displayItem groups:(NSArray<LookinAttributesGroup *> *)groups app:(LKCLIConnectedApp *)app {
    [LKCLIStdIO writeOut:@"%@ (%@)", app.appInfo.appName ?: @"<unknown>", app.appInfo.appBundleIdentifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"display item:"];
    [LKCLIStdIO writeOut:@"  view oid: %@", displayItem.viewObject ? [NSString stringWithFormat:@"%lu", displayItem.viewObject.oid] : @"nil"];
    [LKCLIStdIO writeOut:@"  layer oid: %@", displayItem.layerObject ? [NSString stringWithFormat:@"%lu", displayItem.layerObject.oid] : @"nil"];
    [LKCLIStdIO writeOut:@"  controller oid: %@", displayItem.hostViewControllerObject ? [NSString stringWithFormat:@"%lu", displayItem.hostViewControllerObject.oid] : @"nil"];
    [LKCLIStdIO writeOut:@"  frame: (%.3f, %.3f, %.3f, %.3f)", displayItem.frame.origin.x, displayItem.frame.origin.y, displayItem.frame.size.width, displayItem.frame.size.height];
    [LKCLIStdIO writeOut:@"  hidden: %@", displayItem.isHidden ? @"YES" : @"NO"];
    [LKCLIStdIO writeOut:@"  alpha: %.3f", displayItem.alpha];

    [LKCLIStdIO writeOut:@"object:"];
    [LKCLIStdIO writeOut:@"  oid: %lu", object.oid];
    [LKCLIStdIO writeOut:@"  class: %@", object.rawClassName ?: @"<unknown>"];
    if (object.memoryAddress.length) {
        [LKCLIStdIO writeOut:@"  memory: %@", object.memoryAddress];
    }
    if (object.classChainList.count) {
        [LKCLIStdIO writeOut:@"  class chain:"];
        for (NSString *className in object.classChainList) {
            [LKCLIStdIO writeOut:@"    - %@", className];
        }
    }
    if (object.specialTrace.length) {
        [LKCLIStdIO writeOut:@"  special trace: %@", object.specialTrace];
    }

    [LKCLIStdIO writeOut:@"attributes:"];
    if (groups.count == 0) {
        [LKCLIStdIO writeOut:@"  <none>"];
        return;
    }

    for (LookinAttributesGroup *group in groups) {
        [LKCLIStdIO writeOut:@"  %@", [self displayNameForGroup:group]];
        for (LookinAttributesSection *section in group.attrSections) {
            [LKCLIStdIO writeOut:@"    %@", [self displayNameForSection:section]];
            for (LookinAttribute *attribute in section.attributes) {
                [LKCLIStdIO writeOut:@"      %@: %@", [self displayNameForAttribute:attribute], [self stringForAttributeValue:attribute]];
            }
        }
    }
}

+ (LKCLIExitCode)printJSONWithObject:(LookinObject *)object displayItem:(LookinDisplayItem *)displayItem groups:(NSArray<LookinAttributesGroup *> *)groups app:(LKCLIConnectedApp *)app {
    NSMutableArray<NSDictionary *> *groupObjects = [NSMutableArray arrayWithCapacity:groups.count];
    for (LookinAttributesGroup *group in groups) {
        [groupObjects addObject:[self JSONObjectForGroup:group]];
    }

    NSDictionary *root = @{
        @"app": @{
            @"name": app.appInfo.appName ?: [NSNull null],
            @"bundleIdentifier": app.appInfo.appBundleIdentifier ?: [NSNull null],
            @"device": app.appInfo.deviceDescription ?: [NSNull null],
            @"os": app.appInfo.osDescription ?: [NSNull null],
        },
        @"displayItem": [self JSONObjectForDisplayItem:displayItem],
        @"object": @{
            @"oid": @(object.oid),
            @"className": object.rawClassName ?: [NSNull null],
            @"memoryAddress": object.memoryAddress ?: [NSNull null],
            @"classChain": object.classChainList ?: @[],
            @"specialTrace": object.specialTrace ?: [NSNull null],
        },
        @"attributes": groupObjects,
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

+ (NSDictionary *)JSONObjectForDisplayItem:(LookinDisplayItem *)displayItem {
    CGRect frame = displayItem.frame;
    return @{
        @"viewOid": displayItem.viewObject ? @(displayItem.viewObject.oid) : [NSNull null],
        @"layerOid": displayItem.layerObject ? @(displayItem.layerObject.oid) : [NSNull null],
        @"hostViewControllerOid": displayItem.hostViewControllerObject ? @(displayItem.hostViewControllerObject.oid) : [NSNull null],
        @"className": displayItem.displayingObject.rawClassName ?: [NSNull null],
        @"customTitle": displayItem.customDisplayTitle ?: [NSNull null],
        @"hidden": @(displayItem.isHidden),
        @"alpha": @(displayItem.alpha),
        @"keyWindow": @(displayItem.representedAsKeyWindow),
        @"frame": @{
            @"x": @(frame.origin.x),
            @"y": @(frame.origin.y),
            @"width": @(frame.size.width),
            @"height": @(frame.size.height),
        },
    };
}

+ (NSDictionary *)JSONObjectForGroup:(LookinAttributesGroup *)group {
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray arrayWithCapacity:group.attrSections.count];
    for (LookinAttributesSection *section in group.attrSections) {
        [sections addObject:[self JSONObjectForSection:section]];
    }
    return @{
        @"identifier": group.identifier ?: [NSNull null],
        @"title": [self displayNameForGroup:group],
        @"sections": sections,
    };
}

+ (NSDictionary *)JSONObjectForSection:(LookinAttributesSection *)section {
    NSMutableArray<NSDictionary *> *attributes = [NSMutableArray arrayWithCapacity:section.attributes.count];
    for (LookinAttribute *attribute in section.attributes) {
        [attributes addObject:[self JSONObjectForAttribute:attribute]];
    }
    return @{
        @"identifier": section.identifier ?: [NSNull null],
        @"title": [self displayNameForSection:section],
        @"attributes": attributes,
    };
}

+ (NSDictionary *)JSONObjectForAttribute:(LookinAttribute *)attribute {
    return @{
        @"identifier": attribute.identifier ?: [NSNull null],
        @"title": [self displayNameForAttribute:attribute],
        @"type": [self nameForAttrType:attribute.attrType],
        @"typeCode": @(attribute.attrType),
        @"value": [self JSONObjectForAttributeValue:attribute],
        @"displayValue": [self stringForAttributeValue:attribute],
    };
}

+ (NSString *)displayNameForGroup:(LookinAttributesGroup *)group {
    return group.userCustomTitle.length ? group.userCustomTitle : (group.identifier ?: @"<group>");
}

+ (NSString *)displayNameForSection:(LookinAttributesSection *)section {
    return section.identifier ?: @"<section>";
}

+ (NSString *)displayNameForAttribute:(LookinAttribute *)attribute {
    return attribute.displayTitle.length ? attribute.displayTitle : (attribute.identifier ?: @"<attribute>");
}

+ (NSString *)stringForAttributeValue:(LookinAttribute *)attribute {
    id value = attribute.value;
    if (!value || value == [NSNull null]) {
        return @"nil";
    }

    switch (attribute.attrType) {
        case LookinAttrTypeBOOL:
            return [value boolValue] ? @"YES" : @"NO";
        case LookinAttrTypeCGPoint: {
            CGPoint point = [value pointValue];
            return [NSString stringWithFormat:@"(%.3f, %.3f)", point.x, point.y];
        }
        case LookinAttrTypeCGSize: {
            CGSize size = [value sizeValue];
            return [NSString stringWithFormat:@"(%.3f, %.3f)", size.width, size.height];
        }
        case LookinAttrTypeCGRect: {
            CGRect rect = [value rectValue];
            return [NSString stringWithFormat:@"(%.3f, %.3f, %.3f, %.3f)", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
        }
        case LookinAttrTypeUIEdgeInsets: {
            NSEdgeInsets insets = [value edgeInsetsValue];
            return [NSString stringWithFormat:@"(top %.3f, left %.3f, bottom %.3f, right %.3f)", insets.top, insets.left, insets.bottom, insets.right];
        }
        case LookinAttrTypeUIColor:
            if ([value isKindOfClass:[NSArray class]] && [(NSArray *)value count] >= 4) {
                NSArray *components = value;
                return [NSString stringWithFormat:@"rgba(%.3f, %.3f, %.3f, %.3f)",
                        [components[0] doubleValue],
                        [components[1] doubleValue],
                        [components[2] doubleValue],
                        [components[3] doubleValue]];
            }
            return [value description];
        default:
            return [value description];
    }
}

+ (id)JSONObjectForAttributeValue:(LookinAttribute *)attribute {
    id value = attribute.value;
    if (!value || value == [NSNull null]) {
        return [NSNull null];
    }

    switch (attribute.attrType) {
        case LookinAttrTypeBOOL:
            return @([value boolValue]);
        case LookinAttrTypeCGPoint: {
            CGPoint point = [value pointValue];
            return @{@"x": @(point.x), @"y": @(point.y)};
        }
        case LookinAttrTypeCGSize: {
            CGSize size = [value sizeValue];
            return @{@"width": @(size.width), @"height": @(size.height)};
        }
        case LookinAttrTypeCGRect: {
            CGRect rect = [value rectValue];
            return @{
                @"x": @(rect.origin.x),
                @"y": @(rect.origin.y),
                @"width": @(rect.size.width),
                @"height": @(rect.size.height),
            };
        }
        case LookinAttrTypeUIEdgeInsets: {
            NSEdgeInsets insets = [value edgeInsetsValue];
            return @{
                @"top": @(insets.top),
                @"left": @(insets.left),
                @"bottom": @(insets.bottom),
                @"right": @(insets.right),
            };
        }
        default:
            return [self JSONCompatibleObjectForValue:value];
    }
}

+ (id)JSONCompatibleObjectForValue:(id)value {
    if (!value || value == [NSNull null]) {
        return [NSNull null];
    }
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSNull class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
        for (id item in (NSArray *)value) {
            [array addObject:[self JSONCompatibleObjectForValue:item]];
        }
        return array.copy;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)value count]];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            dictionary[[key description]] = [self JSONCompatibleObjectForValue:obj];
        }];
        return dictionary.copy;
    }
    return [value description] ?: [NSNull null];
}

+ (NSString *)nameForAttrType:(LookinAttrType)attrType {
    switch (attrType) {
        case LookinAttrTypeNone: return @"none";
        case LookinAttrTypeVoid: return @"void";
        case LookinAttrTypeChar: return @"char";
        case LookinAttrTypeInt: return @"int";
        case LookinAttrTypeShort: return @"short";
        case LookinAttrTypeLong: return @"long";
        case LookinAttrTypeLongLong: return @"longLong";
        case LookinAttrTypeUnsignedChar: return @"unsignedChar";
        case LookinAttrTypeUnsignedInt: return @"unsignedInt";
        case LookinAttrTypeUnsignedShort: return @"unsignedShort";
        case LookinAttrTypeUnsignedLong: return @"unsignedLong";
        case LookinAttrTypeUnsignedLongLong: return @"unsignedLongLong";
        case LookinAttrTypeFloat: return @"float";
        case LookinAttrTypeDouble: return @"double";
        case LookinAttrTypeBOOL: return @"bool";
        case LookinAttrTypeSel: return @"selector";
        case LookinAttrTypeClass: return @"class";
        case LookinAttrTypeCGPoint: return @"point";
        case LookinAttrTypeCGVector: return @"vector";
        case LookinAttrTypeCGSize: return @"size";
        case LookinAttrTypeCGRect: return @"rect";
        case LookinAttrTypeCGAffineTransform: return @"affineTransform";
        case LookinAttrTypeUIEdgeInsets: return @"edgeInsets";
        case LookinAttrTypeUIOffset: return @"offset";
        case LookinAttrTypeNSString: return @"string";
        case LookinAttrTypeEnumInt: return @"enumInt";
        case LookinAttrTypeEnumLong: return @"enumLong";
        case LookinAttrTypeUIColor: return @"color";
        case LookinAttrTypeCustomObj: return @"customObject";
        case LookinAttrTypeEnumString: return @"enumString";
        case LookinAttrTypeShadow: return @"shadow";
        case LookinAttrTypeJson: return @"json";
    }
    return @"unknown";
}

@end
