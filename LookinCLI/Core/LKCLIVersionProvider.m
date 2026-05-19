#import "LKCLIVersionProvider.h"
#import "LookinDefines.h"

@implementation LKCLIVersionProvider

+ (NSString *)cliVersion {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *version = info[@"CFBundleShortVersionString"];
    if (version.length > 0) {
        return version;
    }
    return @"0.1.3";
}

+ (NSString *)architectureName {
#if defined(__arm64__)
    return @"arm64";
#elif defined(__x86_64__)
    return @"x86_64";
#else
    return @"unknown";
#endif
}

+ (NSString *)protocolVersionDescription {
    return [NSString stringWithFormat:@"%d", LOOKIN_CLIENT_VERSION];
}

@end
