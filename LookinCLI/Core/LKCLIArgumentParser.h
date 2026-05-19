#import <Foundation/Foundation.h>

@interface LKCLIArgumentParser : NSObject

+ (BOOL)isHelpArgument:(NSString *)argument;
+ (BOOL)consumeValueForOption:(NSString *)option
                    arguments:(NSArray<NSString *> *)arguments
                        index:(NSUInteger *)index
                        value:(NSString **)value
                 errorMessage:(NSString **)errorMessage;
+ (BOOL)parseUnsignedLongValue:(NSString *)value min:(unsigned long)min max:(unsigned long)max result:(unsigned long *)result;
+ (BOOL)parseIntegerValue:(NSString *)value min:(NSInteger)min max:(NSInteger)max result:(NSInteger *)result;
+ (BOOL)parsePositiveOIDValue:(NSString *)value oid:(unsigned long *)oid;

@end
