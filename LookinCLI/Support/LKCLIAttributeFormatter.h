#import <Foundation/Foundation.h>
#import "LookinAttrType.h"

@class LookinAttribute, LookinAttributesGroup, LookinAttributesSection;

@interface LKCLIAttributeFormatter : NSObject

+ (NSArray<LookinAttributesGroup *> *)groups:(NSArray<LookinAttributesGroup *> *)groups matchingFilter:(NSString *)groupFilter;
+ (void)printGroups:(NSArray<LookinAttributesGroup *> *)groups groupFilter:(NSString *)groupFilter baseIndent:(NSString *)baseIndent;
+ (NSArray<NSDictionary *> *)JSONObjectsForGroups:(NSArray<LookinAttributesGroup *> *)groups groupFilter:(NSString *)groupFilter;
+ (NSString *)displayNameForGroup:(LookinAttributesGroup *)group;
+ (NSString *)displayNameForSection:(LookinAttributesSection *)section;
+ (NSString *)displayNameForAttribute:(LookinAttribute *)attribute;
+ (NSString *)stringForAttributeValue:(LookinAttribute *)attribute;
+ (NSString *)nameForAttrType:(LookinAttrType)attrType;

@end
