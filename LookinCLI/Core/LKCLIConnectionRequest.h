#import <Foundation/Foundation.h>

@interface LKCLIConnectionRequest : NSObject

@property(nonatomic, assign) uint32_t type;
@property(nonatomic, assign) uint32_t tag;
@property(nonatomic, assign) NSUInteger receivedDataCount;
@property(nonatomic, copy) void (^succBlock)(id data);
@property(nonatomic, copy) void (^completionBlock)(void);
@property(nonatomic, copy) void (^failBlock)(NSError *error);
@property(nonatomic, assign) NSTimeInterval timeoutInterval;
@property(nonatomic, copy) void (^timeoutBlock)(LKCLIConnectionRequest *request);

- (void)resetTimeoutCount;
- (void)endTimeoutCount;

@end
