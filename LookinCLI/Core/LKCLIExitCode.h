#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, LKCLIExitCode) {
    LKCLIExitCodeOK = 0,
    LKCLIExitCodeGeneralError = 1,
    LKCLIExitCodeUsage = 2,
    LKCLIExitCodeNoApp = 3,
    LKCLIExitCodeAmbiguousApp = 4,
    LKCLIExitCodeConnection = 5,
    LKCLIExitCodeServerVersion = 6,
    LKCLIExitCodeObjectNotFound = 7,
    LKCLIExitCodeUnsupported = 8,
};
