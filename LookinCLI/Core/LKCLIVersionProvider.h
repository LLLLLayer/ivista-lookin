#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LKCLIVersionProvider : NSObject

+ (NSString *)cliVersion;
+ (NSString *)architectureName;
+ (NSString *)protocolVersionDescription;

@end

NS_ASSUME_NONNULL_END
