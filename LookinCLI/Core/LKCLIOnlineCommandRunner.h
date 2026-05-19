#import "LKCLIExitCode.h"
#import <Foundation/Foundation.h>

@class LKCLIAppScanner, LKCLIAppSelection, LKCLIConnectedApp, LookinHierarchyInfo;

typedef LKCLIExitCode (^LKCLISelectedAppBody)(LKCLIAppScanner *scanner, LKCLIConnectedApp *app);
typedef LKCLIExitCode (^LKCLIHierarchyBody)(LKCLIAppScanner *scanner, LKCLIConnectedApp *app, LookinHierarchyInfo *hierarchyInfo);

@interface LKCLIOnlineCommandRunner : NSObject

+ (LKCLIExitCode)withSelectedAppForSelection:(LKCLIAppSelection *)selection
                                 appsTimeout:(NSTimeInterval)appsTimeout
                                        body:(LKCLISelectedAppBody)body;

+ (LKCLIExitCode)withHierarchyForSelection:(LKCLIAppSelection *)selection
                               appsTimeout:(NSTimeInterval)appsTimeout
                          hierarchyTimeout:(NSTimeInterval)hierarchyTimeout
                                      body:(LKCLIHierarchyBody)body;

@end
