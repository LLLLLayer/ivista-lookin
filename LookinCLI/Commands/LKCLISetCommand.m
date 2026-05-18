#import "LKCLISetCommand.h"
#import "LKCLIAppScanner.h"
#import "LKCLIAppSelector.h"
#import "LKCLIAttributeFormatter.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIDisplayItemFetcher.h"
#import "LKCLISignalRunner.h"
#import "LKCLIStdIO.h"
#import "LKCLIVersionProvider.h"
#import "LookinAppInfo.h"
#import "LookinAttribute.h"
#import "LookinAttributeModification.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import "LookinDashboardBlueprint.h"
#import "LookinDefines.h"
#import "LookinDisplayItem.h"
#import <AppKit/AppKit.h>

@implementation LKCLISetCommand

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments {
    LKCLIAppSelection *selection = [LKCLIAppSelection new];
    NSString *attributeIdentifier = nil;
    NSString *rawValue = nil;
    unsigned long oid = 0;
    BOOL json = NO;
    BOOL dryRun = NO;

    for (NSUInteger idx = 0; idx < arguments.count; idx++) {
        NSString *argument = arguments[idx];
        if ([argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"]) {
            [self printHelp];
            return LKCLIExitCodeOK;
        } else if ([argument isEqualToString:@"--json"]) {
            json = YES;
        } else if ([argument isEqualToString:@"--dry-run"]) {
            dryRun = YES;
        } else if ([LKCLIAppSelector isSelectionArgument:argument]) {
            NSString *errorMessage = nil;
            if (![LKCLIAppSelector consumeSelectionArgument:argument arguments:arguments index:&idx selection:selection errorMessage:&errorMessage]) {
                [LKCLIStdIO writeError:@"%@", errorMessage ?: @"error: invalid app selector option"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--oid"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --oid requires a value"];
                return LKCLIExitCodeUsage;
            }
            NSString *oidValue = arguments[++idx];
            if (![LKCLIDisplayItemFetcher parseOIDValue:oidValue oid:&oid]) {
                [LKCLIStdIO writeError:@"error: --oid must be a positive integer"];
                return LKCLIExitCodeUsage;
            }
        } else if ([argument isEqualToString:@"--attr"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --attr requires a value"];
                return LKCLIExitCodeUsage;
            }
            attributeIdentifier = arguments[++idx];
        } else if ([argument isEqualToString:@"--value"]) {
            if (idx + 1 >= arguments.count) {
                [LKCLIStdIO writeError:@"error: --value requires a value"];
                return LKCLIExitCodeUsage;
            }
            rawValue = arguments[++idx];
        } else {
            [LKCLIStdIO writeError:@"error: unknown option '%@'", argument];
            [LKCLIStdIO writeError:@"hint: run 'lookin set --help'"];
            return LKCLIExitCodeUsage;
        }
    }

    if (selection.bundleID.length == 0) {
        [LKCLIStdIO writeError:@"error: --bundle-id is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin apps --json' to find bundle identifiers"];
        return LKCLIExitCodeUsage;
    }
    if (oid == 0) {
        [LKCLIStdIO writeError:@"error: --oid is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin tree --bundle-id %@' to find object ids", selection.bundleID];
        return LKCLIExitCodeUsage;
    }
    if (attributeIdentifier.length == 0) {
        [LKCLIStdIO writeError:@"error: --attr is required"];
        [LKCLIStdIO writeError:@"hint: run 'lookin attrs --bundle-id %@ --oid %lu --json' to find attribute identifiers", selection.bundleID, oid];
        return LKCLIExitCodeUsage;
    }
    if (rawValue == nil) {
        [LKCLIStdIO writeError:@"error: --value is required"];
        return LKCLIExitCodeUsage;
    }

    LKCLIDisplayItemFetchResult *result = nil;
    LKCLIExitCode fetchExitCode = [[LKCLIDisplayItemFetcher new] fetchSelection:selection oid:oid result:&result];
    if (fetchExitCode != LKCLIExitCodeOK) {
        return fetchExitCode;
    }

    LookinAttribute *attribute = [self attributeWithIdentifier:attributeIdentifier inGroups:result.attributeGroups];
    if (!attribute) {
        [LKCLIStdIO writeError:@"error: no attribute found for identifier '%@'", attributeIdentifier];
        [LKCLIStdIO writeError:@"hint: run 'lookin attrs --bundle-id %@ --oid %lu --json'", selection.bundleID, oid];
        return LKCLIExitCodeUsage;
    }
    if (attribute.isUserCustom) {
        [LKCLIStdIO writeError:@"error: custom attributes are not supported by 'lookin set' yet"];
        return LKCLIExitCodeUnsupported;
    }

    SEL setter = [LookinDashboardBlueprint setterWithAttrID:attribute.identifier];
    if (!setter) {
        [LKCLIStdIO writeError:@"error: attribute '%@' is read-only or not settable", attribute.identifier ?: attributeIdentifier];
        return LKCLIExitCodeUnsupported;
    }

    NSString *parseError = nil;
    id parsedValue = [self parsedValueFromString:rawValue attribute:attribute errorMessage:&parseError];
    if (!parsedValue) {
        [LKCLIStdIO writeError:@"error: %@", parseError ?: @"failed to parse --value"];
        return LKCLIExitCodeUsage;
    }

    unsigned long targetOID = [self targetOIDForAttribute:attribute displayItem:result.displayItem];
    if (targetOID == 0) {
        [LKCLIStdIO writeError:@"error: failed to resolve target object for attribute '%@'", attribute.identifier ?: attributeIdentifier];
        return LKCLIExitCodeObjectNotFound;
    }

    if (dryRun) {
        if (json) {
            return [self printJSONWithResult:result attribute:attribute targetOID:targetOID setter:setter rawValue:rawValue parsedValue:parsedValue dryRun:YES];
        }
        [self printTextWithResult:result attribute:attribute targetOID:targetOID setter:setter rawValue:rawValue parsedValue:parsedValue dryRun:YES];
        return LKCLIExitCodeOK;
    }

    LKCLIAppScanner *scanner = [LKCLIAppScanner new];
    LKCLIExitCode selectionExitCode = LKCLIExitCodeOK;
    LKCLIConnectedApp *app = [self selectAppWithScanner:scanner selection:selection exitCode:&selectionExitCode];
    if (!app) {
        [scanner closeAllConnections];
        return selectionExitCode;
    }

    LookinAttributeModification *modification = [LookinAttributeModification new];
    modification.clientReadableVersion = [LKCLIVersionProvider cliVersion];
    modification.targetOid = targetOID;
    modification.setterSelector = setter;
    modification.attrType = attribute.attrType;
    modification.value = parsedValue;

    id modificationValue = nil;
    NSError *modificationError = nil;
    BOOL submitted = [LKCLISignalRunner waitForSignal:[scanner submitInbuiltModification:modification forApp:app] timeout:12 value:&modificationValue error:&modificationError];
    [scanner closeAllConnections];

    if (!submitted) {
        [LKCLIStdIO writeError:@"error: %@", modificationError.localizedDescription ?: @"failed to submit attribute modification"];
        return modificationError.code == LookinErrCode_ObjectNotFound ? LKCLIExitCodeObjectNotFound : LKCLIExitCodeConnection;
    }

    if (json) {
        return [self printJSONWithResult:result attribute:attribute targetOID:targetOID setter:setter rawValue:rawValue parsedValue:parsedValue dryRun:NO];
    }
    [self printTextWithResult:result attribute:attribute targetOID:targetOID setter:setter rawValue:rawValue parsedValue:parsedValue dryRun:NO];
    return LKCLIExitCodeOK;
}

+ (void)printHelp {
    [LKCLIStdIO writeOut:
     @"Usage:\n"
      "  lookin set --bundle-id <bundle-id> --oid <oid> --attr <identifier> --value <value> [--dry-run] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]\n"
      "\n"
      "Modify a settable built-in dashboard attribute. Use 'lookin attrs --json' to find attribute identifiers."];
}

+ (LookinAttribute *)attributeWithIdentifier:(NSString *)identifier inGroups:(NSArray<LookinAttributesGroup *> *)groups {
    for (LookinAttributesGroup *group in groups) {
        for (LookinAttributesSection *section in group.attrSections) {
            for (LookinAttribute *attribute in section.attributes) {
                if ([attribute.identifier isEqualToString:identifier]) {
                    return attribute;
                }
            }
        }
    }
    return nil;
}

+ (unsigned long)targetOIDForAttribute:(LookinAttribute *)attribute displayItem:(LookinDisplayItem *)displayItem {
    if ([LookinDashboardBlueprint isUIViewPropertyWithAttrID:attribute.identifier]) {
        return displayItem.viewObject.oid;
    }
    return displayItem.layerObject.oid;
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

+ (id)parsedValueFromString:(NSString *)rawValue attribute:(LookinAttribute *)attribute errorMessage:(NSString **)errorMessage {
    switch (attribute.attrType) {
        case LookinAttrTypeBOOL:
            return [self parsedBoolFromString:rawValue errorMessage:errorMessage];
        case LookinAttrTypeChar:
        case LookinAttrTypeInt:
        case LookinAttrTypeShort:
        case LookinAttrTypeLong:
        case LookinAttrTypeLongLong:
        case LookinAttrTypeEnumInt:
        case LookinAttrTypeEnumLong:
            return [self parsedSignedNumberFromString:rawValue errorMessage:errorMessage];
        case LookinAttrTypeUnsignedChar:
        case LookinAttrTypeUnsignedInt:
        case LookinAttrTypeUnsignedShort:
        case LookinAttrTypeUnsignedLong:
        case LookinAttrTypeUnsignedLongLong:
            return [self parsedUnsignedNumberFromString:rawValue errorMessage:errorMessage];
        case LookinAttrTypeFloat:
        case LookinAttrTypeDouble:
            return [self parsedDoubleNumberFromString:rawValue errorMessage:errorMessage];
        case LookinAttrTypeNSString:
        case LookinAttrTypeEnumString:
            return rawValue ?: @"";
        case LookinAttrTypeCGPoint:
            return [self parsedPointFromString:rawValue errorMessage:errorMessage];
        case LookinAttrTypeCGSize:
            return [self parsedSizeFromString:rawValue errorMessage:errorMessage];
        case LookinAttrTypeCGRect:
            return [self parsedRectFromString:rawValue errorMessage:errorMessage];
        case LookinAttrTypeUIEdgeInsets:
            return [self parsedInsetsFromString:rawValue errorMessage:errorMessage];
        case LookinAttrTypeUIColor:
            return [self parsedColorComponentsFromString:rawValue errorMessage:errorMessage];
        default:
            if (errorMessage) {
                *errorMessage = [NSString stringWithFormat:@"attribute type '%@' is not supported by 'lookin set' yet", [LKCLIAttributeFormatter nameForAttrType:attribute.attrType]];
            }
            return nil;
    }
}

+ (NSNumber *)parsedBoolFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    NSString *normalized = rawValue.lowercaseString;
    if ([normalized isEqualToString:@"true"] || [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"1"]) {
        return @YES;
    }
    if ([normalized isEqualToString:@"false"] || [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"0"]) {
        return @NO;
    }
    if (errorMessage) {
        *errorMessage = @"expected a boolean value: true/false, yes/no, or 1/0";
    }
    return nil;
}

+ (NSNumber *)parsedSignedNumberFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    NSScanner *scanner = [NSScanner scannerWithString:rawValue];
    long long value = 0;
    if ([scanner scanLongLong:&value] && scanner.isAtEnd) {
        return @(value);
    }
    if (errorMessage) {
        *errorMessage = @"expected an integer value";
    }
    return nil;
}

+ (NSNumber *)parsedUnsignedNumberFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    NSScanner *scanner = [NSScanner scannerWithString:rawValue];
    unsigned long long value = 0;
    if ([scanner scanUnsignedLongLong:&value] && scanner.isAtEnd) {
        return @(value);
    }
    if (errorMessage) {
        *errorMessage = @"expected an unsigned integer value";
    }
    return nil;
}

+ (NSNumber *)parsedDoubleNumberFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    NSScanner *scanner = [NSScanner scannerWithString:rawValue];
    double value = 0;
    if ([scanner scanDouble:&value] && scanner.isAtEnd) {
        return @(value);
    }
    if (errorMessage) {
        *errorMessage = @"expected a number value";
    }
    return nil;
}

+ (NSValue *)parsedPointFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    NSArray<NSNumber *> *numbers = [self parsedDoubleListFromString:rawValue expectedCount:2 errorMessage:errorMessage];
    if (!numbers) {
        return nil;
    }
    return [NSValue valueWithPoint:NSMakePoint(numbers[0].doubleValue, numbers[1].doubleValue)];
}

+ (NSValue *)parsedSizeFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    NSArray<NSNumber *> *numbers = [self parsedDoubleListFromString:rawValue expectedCount:2 errorMessage:errorMessage];
    if (!numbers) {
        return nil;
    }
    return [NSValue valueWithSize:NSMakeSize(numbers[0].doubleValue, numbers[1].doubleValue)];
}

+ (NSValue *)parsedRectFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    NSArray<NSNumber *> *numbers = [self parsedDoubleListFromString:rawValue expectedCount:4 errorMessage:errorMessage];
    if (!numbers) {
        return nil;
    }
    return [NSValue valueWithRect:NSMakeRect(numbers[0].doubleValue, numbers[1].doubleValue, numbers[2].doubleValue, numbers[3].doubleValue)];
}

+ (NSValue *)parsedInsetsFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    NSArray<NSNumber *> *numbers = [self parsedDoubleListFromString:rawValue expectedCount:4 errorMessage:errorMessage];
    if (!numbers) {
        return nil;
    }
    return [NSValue valueWithEdgeInsets:NSEdgeInsetsMake(numbers[0].doubleValue, numbers[1].doubleValue, numbers[2].doubleValue, numbers[3].doubleValue)];
}

+ (NSArray<NSNumber *> *)parsedColorComponentsFromString:(NSString *)rawValue errorMessage:(NSString **)errorMessage {
    if ([rawValue hasPrefix:@"#"]) {
        NSString *hex = [rawValue substringFromIndex:1];
        if (hex.length != 6 && hex.length != 8) {
            if (errorMessage) {
                *errorMessage = @"expected color as #RRGGBB, #RRGGBBAA, or r,g,b[,a]";
            }
            return nil;
        }
        unsigned int rgba = 0;
        NSScanner *scanner = [NSScanner scannerWithString:hex];
        if (![scanner scanHexInt:&rgba] || !scanner.isAtEnd) {
            if (errorMessage) {
                *errorMessage = @"expected a valid hex color";
            }
            return nil;
        }
        unsigned int red = (rgba >> (hex.length == 8 ? 24 : 16)) & 0xff;
        unsigned int green = (rgba >> (hex.length == 8 ? 16 : 8)) & 0xff;
        unsigned int blue = (rgba >> (hex.length == 8 ? 8 : 0)) & 0xff;
        unsigned int alpha = hex.length == 8 ? (rgba & 0xff) : 0xff;
        return @[@(red / 255.0), @(green / 255.0), @(blue / 255.0), @(alpha / 255.0)];
    }

    NSArray<NSNumber *> *numbers = [self parsedDoubleListFromString:rawValue minCount:3 maxCount:4 errorMessage:errorMessage];
    if (!numbers) {
        return nil;
    }

    NSMutableArray<NSNumber *> *components = [numbers mutableCopy];
    if (components.count == 3) {
        [components addObject:@1];
    }
    for (NSUInteger idx = 0; idx < components.count; idx++) {
        double value = components[idx].doubleValue;
        value = value > 1 ? value / 255.0 : value;
        if (value < 0 || value > 1) {
            if (errorMessage) {
                *errorMessage = @"expected color components in 0...1 or 0...255 range";
            }
            return nil;
        }
        components[idx] = @(value);
    }
    return components.copy;
}

+ (NSArray<NSNumber *> *)parsedDoubleListFromString:(NSString *)rawValue expectedCount:(NSUInteger)expectedCount errorMessage:(NSString **)errorMessage {
    return [self parsedDoubleListFromString:rawValue minCount:expectedCount maxCount:expectedCount errorMessage:errorMessage];
}

+ (NSArray<NSNumber *> *)parsedDoubleListFromString:(NSString *)rawValue minCount:(NSUInteger)minCount maxCount:(NSUInteger)maxCount errorMessage:(NSString **)errorMessage {
    NSString *normalized = [rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *wrappers = [NSCharacterSet characterSetWithCharactersInString:@"()[]{}"];
    normalized = [[normalized componentsSeparatedByCharactersInSet:wrappers] componentsJoinedByString:@""];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@", "];
    NSArray<NSString *> *parts = [normalized componentsSeparatedByCharactersInSet:separators];
    NSMutableArray<NSNumber *> *numbers = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length == 0) {
            continue;
        }
        NSNumber *number = [self parsedDoubleNumberFromString:part errorMessage:nil];
        if (!number) {
            if (errorMessage) {
                *errorMessage = @"expected comma-separated numbers";
            }
            return nil;
        }
        [numbers addObject:number];
    }
    if (numbers.count < minCount || numbers.count > maxCount) {
        if (errorMessage) {
            if (minCount == maxCount) {
                *errorMessage = [NSString stringWithFormat:@"expected %lu comma-separated numbers", (unsigned long)minCount];
            } else {
                *errorMessage = [NSString stringWithFormat:@"expected %lu to %lu comma-separated numbers", (unsigned long)minCount, (unsigned long)maxCount];
            }
        }
        return nil;
    }
    return numbers.copy;
}

+ (void)printTextWithResult:(LKCLIDisplayItemFetchResult *)result
                  attribute:(LookinAttribute *)attribute
                  targetOID:(unsigned long)targetOID
                     setter:(SEL)setter
                   rawValue:(NSString *)rawValue
                parsedValue:(id)parsedValue
                     dryRun:(BOOL)dryRun {
    [LKCLIStdIO writeOut:@"%@ (%@)", result.app.appInfo.appName ?: @"<unknown>", result.app.appInfo.appBundleIdentifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"object: %lu", result.object.oid];
    [LKCLIStdIO writeOut:@"attribute: %@", attribute.identifier ?: @"<unknown>"];
    [LKCLIStdIO writeOut:@"target oid: %lu", targetOID];
    [LKCLIStdIO writeOut:@"setter: %@", NSStringFromSelector(setter)];
    [LKCLIStdIO writeOut:@"old value: %@", [LKCLIAttributeFormatter stringForAttributeValue:attribute]];
    [LKCLIStdIO writeOut:@"new value: %@", [self displayStringForParsedValue:parsedValue fallback:rawValue]];
    [LKCLIStdIO writeOut:@"status: %@", dryRun ? @"dry run" : @"submitted"];
}

+ (LKCLIExitCode)printJSONWithResult:(LKCLIDisplayItemFetchResult *)result
                            attribute:(LookinAttribute *)attribute
                            targetOID:(unsigned long)targetOID
                               setter:(SEL)setter
                             rawValue:(NSString *)rawValue
                          parsedValue:(id)parsedValue
                               dryRun:(BOOL)dryRun {
    NSDictionary *root = @{
        @"app": @{
            @"name": result.app.appInfo.appName ?: [NSNull null],
            @"bundleIdentifier": result.app.appInfo.appBundleIdentifier ?: [NSNull null],
            @"device": result.app.appInfo.deviceDescription ?: [NSNull null],
            @"os": result.app.appInfo.osDescription ?: [NSNull null],
        },
        @"object": @{
            @"oid": @(result.object.oid),
            @"className": result.object.rawClassName ?: [NSNull null],
        },
        @"attribute": @{
            @"identifier": attribute.identifier ?: [NSNull null],
            @"title": [LKCLIAttributeFormatter displayNameForAttribute:attribute],
            @"oldValue": [LKCLIAttributeFormatter stringForAttributeValue:attribute],
        },
        @"targetOid": @(targetOID),
        @"setter": NSStringFromSelector(setter),
        @"rawValue": rawValue ?: [NSNull null],
        @"parsedValue": [self JSONCompatibleObjectForValue:parsedValue],
        @"dryRun": @(dryRun),
        @"submitted": @(!dryRun),
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

+ (NSString *)displayStringForParsedValue:(id)value fallback:(NSString *)fallback {
    if ([value isKindOfClass:[NSValue class]]) {
        return [value description];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
        for (id item in (NSArray *)value) {
            [parts addObject:[item description] ?: @"<nil>"];
        }
        return [parts componentsJoinedByString:@", "];
    }
    return [value description] ?: fallback ?: @"<nil>";
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
    if ([value isKindOfClass:[NSValue class]]) {
        return [value description] ?: [NSNull null];
    }
    return [value description] ?: [NSNull null];
}

@end
