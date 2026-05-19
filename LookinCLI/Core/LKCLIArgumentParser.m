#import "LKCLIArgumentParser.h"
#import <limits.h>
#import <stdlib.h>

@implementation LKCLIArgumentParser

+ (BOOL)isHelpArgument:(NSString *)argument {
    return [argument isEqualToString:@"--help"] || [argument isEqualToString:@"-h"];
}

+ (BOOL)argumentsContainHelp:(NSArray<NSString *> *)arguments {
    for (NSString *argument in arguments) {
        if ([self isHelpArgument:argument]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)consumeValueForOption:(NSString *)option
                    arguments:(NSArray<NSString *> *)arguments
                        index:(NSUInteger *)index
                        value:(NSString **)value
                 errorMessage:(NSString **)errorMessage {
    if (index == NULL) {
        if (errorMessage) {
            *errorMessage = @"internal argument parser error";
        }
        return NO;
    }
    if (*index + 1 >= arguments.count) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"error: %@ requires a value", option];
        }
        return NO;
    }
    if (value) {
        *value = arguments[++(*index)];
    } else {
        (*index)++;
    }
    return YES;
}

+ (BOOL)parseUnsignedLongValue:(NSString *)value min:(unsigned long)min max:(unsigned long)max result:(unsigned long *)result {
    if (value.length == 0) {
        return NO;
    }

    NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
    if ([value rangeOfCharacterFromSet:digits.invertedSet].location != NSNotFound) {
        return NO;
    }

    NSString *normalizedValue = value;
    while (normalizedValue.length > 1 && [normalizedValue hasPrefix:@"0"]) {
        normalizedValue = [normalizedValue substringFromIndex:1];
    }

    NSString *maxValue = [NSString stringWithFormat:@"%lu", max];
    if (normalizedValue.length > maxValue.length ||
        (normalizedValue.length == maxValue.length && [normalizedValue compare:maxValue] == NSOrderedDescending)) {
        return NO;
    }

    unsigned long parsedValue = strtoul(value.UTF8String, NULL, 10);
    if (parsedValue < min || parsedValue > max) {
        return NO;
    }
    if (result) {
        *result = parsedValue;
    }
    return YES;
}

+ (BOOL)parseIntegerValue:(NSString *)value min:(NSInteger)min max:(NSInteger)max result:(NSInteger *)result {
    unsigned long parsedValue = 0;
    if (min < 0 || max < min || ![self parseUnsignedLongValue:value min:(unsigned long)min max:(unsigned long)max result:&parsedValue]) {
        return NO;
    }
    if (result) {
        *result = (NSInteger)parsedValue;
    }
    return YES;
}

+ (BOOL)parsePositiveOIDValue:(NSString *)value oid:(unsigned long *)oid {
    return [self parseUnsignedLongValue:value min:1 max:ULONG_MAX result:oid];
}

@end
