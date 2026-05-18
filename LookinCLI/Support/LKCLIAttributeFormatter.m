#import "LKCLIAttributeFormatter.h"
#import "LKCLIStdIO.h"
#import "LookinAttribute.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import <AppKit/AppKit.h>

@implementation LKCLIAttributeFormatter

+ (NSArray<LookinAttributesGroup *> *)groups:(NSArray<LookinAttributesGroup *> *)groups matchingFilter:(NSString *)groupFilter {
    if (groupFilter.length == 0) {
        return groups ?: @[];
    }

    NSMutableArray<LookinAttributesGroup *> *matchedGroups = [NSMutableArray array];
    for (LookinAttributesGroup *group in groups) {
        if ([self group:group matchesFilter:groupFilter]) {
            [matchedGroups addObject:group];
        }
    }
    return matchedGroups.copy;
}

+ (BOOL)group:(LookinAttributesGroup *)group matchesFilter:(NSString *)groupFilter {
    NSArray<NSString *> *candidates = @[
        group.identifier ?: @"",
        group.userCustomTitle ?: @"",
        [self displayNameForGroup:group] ?: @"",
    ];
    for (NSString *candidate in candidates) {
        if ([candidate rangeOfString:groupFilter options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

+ (void)printGroups:(NSArray<LookinAttributesGroup *> *)groups groupFilter:(NSString *)groupFilter baseIndent:(NSString *)baseIndent {
    NSArray<LookinAttributesGroup *> *displayGroups = [self groups:groups matchingFilter:groupFilter];
    NSString *groupIndent = baseIndent ?: @"";
    NSString *sectionIndent = [groupIndent stringByAppendingString:@"  "];
    NSString *attributeIndent = [sectionIndent stringByAppendingString:@"  "];

    if (displayGroups.count == 0) {
        [LKCLIStdIO writeOut:@"%@%@", groupIndent, groupFilter.length ? @"<no matching groups>" : @"<none>"];
        return;
    }

    for (LookinAttributesGroup *group in displayGroups) {
        [LKCLIStdIO writeOut:@"%@%@", groupIndent, [self displayNameForGroup:group]];
        for (LookinAttributesSection *section in group.attrSections) {
            [LKCLIStdIO writeOut:@"%@%@", sectionIndent, [self displayNameForSection:section]];
            for (LookinAttribute *attribute in section.attributes) {
                [LKCLIStdIO writeOut:@"%@%@: %@", attributeIndent, [self displayNameForAttribute:attribute], [self stringForAttributeValue:attribute]];
            }
        }
    }
}

+ (NSArray<NSDictionary *> *)JSONObjectsForGroups:(NSArray<LookinAttributesGroup *> *)groups groupFilter:(NSString *)groupFilter {
    NSArray<LookinAttributesGroup *> *displayGroups = [self groups:groups matchingFilter:groupFilter];
    NSMutableArray<NSDictionary *> *groupObjects = [NSMutableArray arrayWithCapacity:displayGroups.count];
    for (LookinAttributesGroup *group in displayGroups) {
        [groupObjects addObject:[self JSONObjectForGroup:group]];
    }
    return groupObjects.copy;
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
        @"isUserCustom": @(attribute.isUserCustom),
        @"customSetterID": attribute.customSetterID ?: [NSNull null],
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
