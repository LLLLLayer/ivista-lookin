#import <Foundation/Foundation.h>

@class LookinAppInfo, Lookin_PTChannel;

@interface LKCLIConnectedApp : NSObject

@property(nonatomic, strong) LookinAppInfo *appInfo;
@property(nonatomic, strong) Lookin_PTChannel *channel;
@property(nonatomic, strong) NSError *serverVersionError;
@property(nonatomic, copy) NSString *transport;
@property(nonatomic, assign) NSInteger port;
@property(nonatomic, strong) NSNumber *deviceID;

@end
