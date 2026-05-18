#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LKCLIStdIO : NSObject

+ (void)writeOut:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)writeError:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

@end

NS_ASSUME_NONNULL_END
