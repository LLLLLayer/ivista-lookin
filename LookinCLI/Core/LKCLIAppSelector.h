#import <Foundation/Foundation.h>
#import "LKCLIExitCode.h"

@class LKCLIConnectedApp;

@interface LKCLIAppSelection : NSObject

@property(nonatomic, copy) NSString *bundleID;
@property(nonatomic, copy) NSString *transport;
@property(nonatomic, strong) NSNumber *port;
@property(nonatomic, strong) NSNumber *deviceID;

@end

@interface LKCLIAppSelector : NSObject

+ (BOOL)isSelectionArgument:(NSString *)argument;
+ (BOOL)consumeSelectionArgument:(NSString *)argument
                       arguments:(NSArray<NSString *> *)arguments
                           index:(NSUInteger *)index
                       selection:(LKCLIAppSelection *)selection
                    errorMessage:(NSString **)errorMessage;
+ (NSArray<LKCLIConnectedApp *> *)appsFromAppsValue:(id)appsValue
                                           selection:(LKCLIAppSelection *)selection
                                includeServerErrors:(BOOL)includeServerErrors;
+ (NSString *)selectionHelpSuffix;

- (LKCLIConnectedApp *)selectAppFromAppsValue:(id)appsValue
                                    selection:(LKCLIAppSelection *)selection
                                     exitCode:(LKCLIExitCode *)exitCode;

@end
