#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@interface LKCLITreeCommand : NSObject

+ (LKCLIExitCode)runWithArguments:(NSArray<NSString *> *)arguments;
+ (LKCLIExitCode)runFindWithArguments:(NSArray<NSString *> *)arguments;
+ (BOOL)parseDepthValue:(NSString *)value depth:(NSInteger *)depth;
+ (BOOL)parseOIDValue:(NSString *)value oid:(unsigned long *)oid;
+ (BOOL)parseLimitValue:(NSString *)value limit:(NSUInteger *)limit;
+ (void)printTextWithItems:(NSArray *)items app:(id)app depth:(NSInteger)depth filter:(NSString *)filter focusOID:(unsigned long)focusOID;
+ (LKCLIExitCode)printJSONWithItems:(NSArray *)displayItems app:(id)app depth:(NSInteger)depth filter:(NSString *)filter focusOID:(unsigned long)focusOID;
+ (NSArray *)filteredItemsFromItems:(NSArray *)items filter:(NSString *)filter;
+ (id)firstItemInItems:(NSArray *)items matchingOID:(unsigned long)oid;
+ (NSArray<NSDictionary *> *)matchesInItems:(NSArray *)items query:(NSString *)query exactOID:(unsigned long)exactOID limit:(NSUInteger)limit;
+ (void)printFindTextWithMatches:(NSArray<NSDictionary *> *)matches app:(id)app query:(NSString *)query limit:(NSUInteger)limit;
+ (LKCLIExitCode)printFindJSONWithMatches:(NSArray<NSDictionary *> *)matches app:(id)app query:(NSString *)query limit:(NSUInteger)limit;

@end
