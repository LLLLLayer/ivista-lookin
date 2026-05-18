#import "LKCLIAppScanner.h"
#import "LKCLIConnectedApp.h"
#import "LKCLIConnectionRequest.h"
#import "LKCLIVersionProvider.h"
#import "Lookin_PTChannel.h"
#import "LookinDefines.h"
#import "LookinConnectionAttachment.h"
#import "LookinConnectionResponseAttachment.h"
#import "LookinAppInfo.h"
#import <netinet/in.h>

static const NSTimeInterval LKCLIAppScannerInitialDiscoveryDelay = 0.35;
static const NSTimeInterval LKCLIAppScannerRetryDiscoveryDelay = 0.45;

@interface LKCLIConnectionPort : NSObject

@property(nonatomic, assign) NSInteger portNumber;
@property(nonatomic, copy) NSString *transport;
@property(nonatomic, strong) NSNumber *deviceID;
@property(nonatomic, strong) Lookin_PTChannel *connectedChannel;

@end

@implementation LKCLIConnectionPort

@end

@interface LKCLIAppScanner () <Lookin_PTChannelDelegate>

@property(nonatomic, copy) NSArray<LKCLIConnectionPort *> *simulatorPorts;
@property(nonatomic, strong) NSMutableArray<LKCLIConnectionPort *> *usbPorts;
@property(nonatomic, strong) NSMapTable<Lookin_PTChannel *, NSMutableSet<LKCLIConnectionRequest *> *> *activeRequestsByChannel;
@property(nonatomic, strong) NSMapTable<Lookin_PTChannel *, LKCLIConnectionPort *> *portsByChannel;

- (RACSignal *)fetchDataWithRequestType:(uint32_t)requestType data:(NSObject *)data forApp:(LKCLIConnectedApp *)app;

@end

@implementation LKCLIAppScanner

- (instancetype)init {
    if (self = [super init]) {
        _usbPorts = [NSMutableArray array];
        _activeRequestsByChannel = [NSMapTable weakToStrongObjectsMapTable];
        _portsByChannel = [NSMapTable weakToStrongObjectsMapTable];

        NSMutableArray<LKCLIConnectionPort *> *simulatorPorts = [NSMutableArray array];
        for (int port = LookinSimulatorIPv4PortNumberStart; port <= LookinSimulatorIPv4PortNumberEnd; port++) {
            LKCLIConnectionPort *item = [LKCLIConnectionPort new];
            item.portNumber = port;
            item.transport = @"simulator";
            [simulatorPorts addObject:item];
        }
        _simulatorPorts = simulatorPorts.copy;

        [self startListeningForUSBDevices];
    }
    return self;
}

- (RACSignal *)fetchAppsWithImages:(BOOL)needImages {
    return [[self fetchAppsAttemptWithImages:needImages delay:LKCLIAppScannerInitialDiscoveryDelay] flattenMap:^__kindof RACSignal * _Nullable(id appsValue) {
        if ([appsValue isKindOfClass:[NSArray class]] && [(NSArray *)appsValue count] == 0) {
            return [self fetchAppsAttemptWithImages:needImages delay:LKCLIAppScannerRetryDiscoveryDelay];
        }
        return [RACSignal return:appsValue];
    }];
}

- (RACSignal *)fetchAppsAttemptWithImages:(BOOL)needImages delay:(NSTimeInterval)delay {
    return [[[[[RACSignal return:nil] delay:delay] flattenMap:^__kindof RACSignal * _Nullable(id value) {
        return [self tryToConnectAllPorts];
    }] flattenMap:^__kindof RACSignal * _Nullable(NSArray<Lookin_PTChannel *> *connectedChannels) {
        if (connectedChannels.count == 0) {
            return [RACSignal return:@[]];
        }

        NSDictionary *params = @{@"needImages": @(needImages), @"local": @[]};
        NSMutableArray<RACSignal *> *signals = [NSMutableArray arrayWithCapacity:connectedChannels.count];
        for (Lookin_PTChannel *channel in connectedChannels) {
            RACSignal *signal = [[self requestWithType:LookinRequestTypeApp data:params channel:channel] catch:^RACSignal * _Nonnull(NSError * _Nonnull error) {
                if (error.code == LookinErrCode_ServerVersionTooHigh || error.code == LookinErrCode_ServerVersionTooLow) {
                    return [RACSignal return:error];
                }
                return [RACSignal return:nil];
            }];
            [signals addObject:signal];
        }
        return [RACSignal zip:signals];
    }] map:^id _Nullable(RACTuple *tuple) {
        NSMutableArray<LKCLIConnectedApp *> *apps = [NSMutableArray array];
        for (id value in tuple.allObjects) {
            if (value == [NSNull null]) {
                continue;
            }
            if ([value isKindOfClass:[NSError class]]) {
                LKCLIConnectedApp *app = [LKCLIConnectedApp new];
                app.serverVersionError = value;
                [apps addObject:app];
                continue;
            }
            if (![value isKindOfClass:[RACTuple class]]) {
                continue;
            }

            RACTuple *responseTuple = value;
            LookinConnectionResponseAttachment *response = responseTuple.first;
            Lookin_PTChannel *channel = responseTuple.second;
            if (response.error || ![response.data isKindOfClass:[LookinAppInfo class]]) {
                continue;
            }

            LKCLIConnectedApp *app = [LKCLIConnectedApp new];
            app.appInfo = response.data;
            app.channel = channel;

            LKCLIConnectionPort *port = [self.portsByChannel objectForKey:channel];
            app.transport = port.transport;
            app.port = port.portNumber;
            app.deviceID = port.deviceID;
            [apps addObject:app];
        }
        return apps.copy;
    }];
}

- (RACSignal *)fetchHierarchyForApp:(LKCLIConnectedApp *)app {
    NSDictionary *params = @{@"clientVersion": [LKCLIVersionProvider cliVersion]};
    return [self fetchDataWithRequestType:LookinRequestTypeHierarchy data:params forApp:app];
}

- (RACSignal *)fetchHierarchyDetailsWithTaskPackages:(NSArray *)packages forApp:(LKCLIConnectedApp *)app {
    return [self fetchDataWithRequestType:LookinRequestTypeHierarchyDetails data:packages forApp:app];
}

- (RACSignal *)fetchObjectWithOID:(unsigned long)oid forApp:(LKCLIConnectedApp *)app {
    if (oid == 0) {
        return [RACSignal error:LookinErr_Inner];
    }
    return [self fetchDataWithRequestType:LookinRequestTypeFetchObject data:@(oid) forApp:app];
}

- (RACSignal *)fetchAttributeGroupsWithOID:(unsigned long)oid forApp:(LKCLIConnectedApp *)app {
    if (oid == 0) {
        return [RACSignal error:LookinErr_Inner];
    }
    return [self fetchDataWithRequestType:LookinRequestTypeAllAttrGroups data:@(oid) forApp:app];
}

- (RACSignal *)fetchDataWithRequestType:(uint32_t)requestType data:(NSObject *)data forApp:(LKCLIConnectedApp *)app {
    if (!app.channel) {
        return [RACSignal error:LookinErr_NoConnect];
    }

    return [[self requestWithType:requestType data:data channel:app.channel] flattenMap:^__kindof RACSignal * _Nullable(RACTuple *tuple) {
        LookinConnectionResponseAttachment *attachment = tuple.first;
        if (attachment.error) {
            return [RACSignal error:attachment.error];
        }
        return [RACSignal return:attachment.data];
    }];
}

- (void)closeAllConnections {
    for (LKCLIConnectionPort *port in self.simulatorPorts) {
        [port.connectedChannel close];
        port.connectedChannel = nil;
    }
    for (LKCLIConnectionPort *port in self.usbPorts) {
        [port.connectedChannel close];
        port.connectedChannel = nil;
    }
}

#pragma mark - Connect

- (RACSignal *)tryToConnectAllPorts {
    return [[RACSignal zip:@[[self tryToConnectSimulatorPorts], [self tryToConnectUSBPorts]]] map:^id _Nullable(RACTuple *value) {
        NSArray *simulatorChannels = value.first ?: @[];
        NSArray *usbChannels = value.second ?: @[];
        return [simulatorChannels arrayByAddingObjectsFromArray:usbChannels];
    }];
}

- (RACSignal *)tryToConnectSimulatorPorts {
    NSMutableArray<RACSignal *> *signals = [NSMutableArray arrayWithCapacity:self.simulatorPorts.count];
    for (LKCLIConnectionPort *port in self.simulatorPorts) {
        RACSignal *signal = [[self connectToSimulatorPort:port] catch:^RACSignal * _Nonnull(NSError * _Nonnull error) {
            return [RACSignal return:nil];
        }];
        [signals addObject:signal];
    }
    return [[RACSignal zip:signals] map:^id _Nullable(RACTuple *tuple) {
        return [self connectedChannelsFromTuple:tuple];
    }];
}

- (RACSignal *)tryToConnectUSBPorts {
    if (self.usbPorts.count == 0) {
        return [RACSignal return:@[]];
    }

    NSMutableArray<RACSignal *> *signals = [NSMutableArray arrayWithCapacity:self.usbPorts.count];
    for (LKCLIConnectionPort *port in self.usbPorts.copy) {
        RACSignal *signal = [[self connectToUSBPort:port] catch:^RACSignal * _Nonnull(NSError * _Nonnull error) {
            return [RACSignal return:nil];
        }];
        [signals addObject:signal];
    }
    return [[RACSignal zip:signals] map:^id _Nullable(RACTuple *tuple) {
        return [self connectedChannelsFromTuple:tuple];
    }];
}

- (NSArray<Lookin_PTChannel *> *)connectedChannelsFromTuple:(RACTuple *)tuple {
    NSMutableArray<Lookin_PTChannel *> *channels = [NSMutableArray array];
    for (id value in tuple.allObjects) {
        if (value != [NSNull null] && [value isKindOfClass:[Lookin_PTChannel class]]) {
            [channels addObject:value];
        }
    }
    return channels.copy;
}

- (RACSignal *)connectToSimulatorPort:(LKCLIConnectionPort *)port {
    return [RACSignal createSignal:^RACDisposable * _Nullable(id<RACSubscriber> subscriber) {
        if (port.connectedChannel) {
            [subscriber sendNext:port.connectedChannel];
            [subscriber sendCompleted];
            return nil;
        }

        Lookin_PTChannel *channel = [Lookin_PTChannel channelWithDelegate:self];
        [channel connectToPort:(int)port.portNumber IPv4Address:INADDR_LOOPBACK callback:^(NSError *error, Lookin_PTAddress *address) {
            if (error) {
                [channel close];
                [subscriber sendError:error];
            } else {
                port.connectedChannel = channel;
                [self.portsByChannel setObject:port forKey:channel];
                [subscriber sendNext:channel];
                [subscriber sendCompleted];
            }
        }];
        return nil;
    }];
}

- (RACSignal *)connectToUSBPort:(LKCLIConnectionPort *)port {
    return [RACSignal createSignal:^RACDisposable * _Nullable(id<RACSubscriber> subscriber) {
        if (port.connectedChannel) {
            [subscriber sendNext:port.connectedChannel];
            [subscriber sendCompleted];
            return nil;
        }

        Lookin_PTChannel *channel = [Lookin_PTChannel channelWithDelegate:self];
        [channel connectToPort:(int)port.portNumber overUSBHub:Lookin_PTUSBHub.sharedHub deviceID:port.deviceID callback:^(NSError *error) {
            if (error) {
                [channel close];
                [subscriber sendError:error];
            } else {
                port.connectedChannel = channel;
                [self.portsByChannel setObject:port forKey:channel];
                [subscriber sendNext:channel];
                [subscriber sendCompleted];
            }
        }];
        return nil;
    }];
}

#pragma mark - Request

- (RACSignal *)requestWithType:(uint32_t)requestType data:(NSObject *)requestData channel:(Lookin_PTChannel *)channel {
    return [RACSignal createSignal:^RACDisposable * _Nullable(id<RACSubscriber> subscriber) {
        NSTimeInterval pingTimeout = (requestType == LookinRequestTypeApp) ? 0.5 : 2;

        [self requestFrameWithType:LookinRequestTypePing channel:channel data:nil timeout:pingTimeout success:^(LookinConnectionResponseAttachment *pingResponse) {
            NSError *serverVersionError = [self serverVersionErrorWithPingResponse:pingResponse];
            if (serverVersionError) {
                [subscriber sendError:serverVersionError];
                return;
            }

            [self requestFrameWithType:requestType channel:channel data:requestData timeout:5 success:^(id responseData) {
                [subscriber sendNext:[RACTuple tupleWithObjects:responseData, channel, nil]];
            } failure:^(NSError *error) {
                [subscriber sendError:error];
            } completion:^{
                [subscriber sendCompleted];
            }];
        } failure:^(NSError *error) {
            [subscriber sendError:error];
        } completion:nil];

        return nil;
    }];
}

- (void)requestFrameWithType:(uint32_t)requestType
                     channel:(Lookin_PTChannel *)channel
                        data:(NSObject *)data
                     timeout:(NSTimeInterval)timeout
                     success:(void (^)(id data))success
                     failure:(void (^)(NSError *error))failure
                  completion:(void (^)(void))completion {
    if (!channel || !channel.isConnected) {
        if (failure) {
            failure(LookinErr_NoConnect);
        }
        return;
    }

    NSMutableSet<LKCLIConnectionRequest *> *activeRequests = [self activeRequestsForChannel:channel createIfNeeded:YES];
    if (requestType != LookinRequestTypePing) {
        NSMutableSet<LKCLIConnectionRequest *> *discardedRequests = [NSMutableSet set];
        for (LKCLIConnectionRequest *request in activeRequests) {
            if (request.type == requestType) {
                [discardedRequests addObject:request];
            }
        }
        for (LKCLIConnectionRequest *request in discardedRequests) {
            [request endTimeoutCount];
            if (request.failBlock) {
                request.failBlock([NSError errorWithDomain:LookinErrorDomain
                                                      code:LookinErrCode_Discard
                                                  userInfo:@{NSLocalizedDescriptionKey: @"The request was discarded by a newer request."}]);
            }
            [activeRequests removeObject:request];
        }
    }

    LKCLIConnectionRequest *request = [LKCLIConnectionRequest new];
    request.type = requestType;
    request.tag = (uint32_t)[[NSDate date] timeIntervalSince1970];
    request.succBlock = success;
    request.failBlock = failure;
    request.completionBlock = completion;
    request.timeoutInterval = timeout;
    __weak typeof(self) weakSelf = self;
    __weak typeof(channel) weakChannel = channel;
    request.timeoutBlock = ^(LKCLIConnectionRequest *timedOutRequest) {
        __strong typeof(weakSelf) self = weakSelf;
        __strong typeof(weakChannel) channel = weakChannel;
        NSError *error = [NSError errorWithDomain:LookinErrorDomain
                                             code:LookinErrCode_Timeout
                                         userInfo:@{NSLocalizedDescriptionKey: @"Request timeout"}];
        if (timedOutRequest.failBlock) {
            timedOutRequest.failBlock(error);
        }
        [[self activeRequestsForChannel:channel createIfNeeded:NO] removeObject:timedOutRequest];
    };

    LookinConnectionAttachment *attachment = [LookinConnectionAttachment new];
    attachment.data = data;
    NSError *archiveError = nil;
    NSData *archiveData = [NSKeyedArchiver archivedDataWithRootObject:attachment requiringSecureCoding:YES error:&archiveError];
    if (archiveError) {
        if (failure) {
            failure(archiveError);
        }
        return;
    }

    dispatch_data_t payload = [archiveData createReferencingDispatchData];
    [channel sendFrameOfType:requestType tag:request.tag withPayload:payload callback:^(NSError *sendError) {
        if (sendError) {
            if (failure) {
                failure([NSError errorWithDomain:LookinErrorDomain
                                            code:LookinErrCode_PeerTalk
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to send request."}]);
            }
        } else {
            [activeRequests addObject:request];
            [request resetTimeoutCount];
        }
    }];
}

- (NSError *)serverVersionErrorWithPingResponse:(LookinConnectionResponseAttachment *)pingResponse {
    int serverVersion = pingResponse.lookinServerVersion;
    if (serverVersion == -1 || serverVersion == 100 || serverVersion < LOOKIN_SUPPORTED_SERVER_MIN) {
        return [NSError errorWithDomain:LookinErrorDomain
                                   code:LookinErrCode_ServerVersionTooLow
                               userInfo:@{NSLocalizedDescriptionKey: @"LookinServer version is too low."}];
    }
    if (serverVersion > LOOKIN_SUPPORTED_SERVER_MAX) {
        return [NSError errorWithDomain:LookinErrorDomain
                                   code:LookinErrCode_ServerVersionTooHigh
                               userInfo:@{NSLocalizedDescriptionKey: @"LookinServer version is too high for this CLI."}];
    }
    return nil;
}

- (NSMutableSet<LKCLIConnectionRequest *> *)activeRequestsForChannel:(Lookin_PTChannel *)channel createIfNeeded:(BOOL)createIfNeeded {
    if (!channel) {
        return nil;
    }
    NSMutableSet<LKCLIConnectionRequest *> *requests = [self.activeRequestsByChannel objectForKey:channel];
    if (!requests && createIfNeeded) {
        requests = [NSMutableSet set];
        [self.activeRequestsByChannel setObject:requests forKey:channel];
    }
    return requests;
}

#pragma mark - USB

- (void)startListeningForUSBDevices {
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserverForName:Lookin_PTUSBDeviceDidAttachNotification object:Lookin_PTUSBHub.sharedHub queue:nil usingBlock:^(NSNotification *note) {
        NSNumber *deviceID = note.userInfo[@"DeviceID"];
        if (!deviceID) {
            return;
        }
        for (int port = LookinUSBDeviceIPv4PortNumberStart; port <= LookinUSBDeviceIPv4PortNumberEnd; port++) {
            LKCLIConnectionPort *item = [LKCLIConnectionPort new];
            item.portNumber = port;
            item.transport = @"usb";
            item.deviceID = deviceID;
            [self.usbPorts addObject:item];
        }
    }];

    [notificationCenter addObserverForName:Lookin_PTUSBDeviceDidDetachNotification object:Lookin_PTUSBHub.sharedHub queue:nil usingBlock:^(NSNotification *note) {
        NSNumber *deviceID = note.userInfo[@"DeviceID"];
        if (!deviceID) {
            return;
        }
        NSMutableArray<LKCLIConnectionPort *> *remainingPorts = [NSMutableArray array];
        for (LKCLIConnectionPort *port in self.usbPorts) {
            if ([port.deviceID isEqual:deviceID]) {
                [port.connectedChannel close];
            } else {
                [remainingPorts addObject:port];
            }
        }
        self.usbPorts = remainingPorts;
    }];
}

#pragma mark - Lookin_PTChannelDelegate

- (BOOL)ioFrameChannel:(Lookin_PTChannel *)channel shouldAcceptFrameOfType:(uint32_t)type tag:(uint32_t)tag payloadSize:(uint32_t)payloadSize {
    for (LKCLIConnectionRequest *request in [self activeRequestsForChannel:channel createIfNeeded:NO]) {
        if (request.type == type && request.tag == tag) {
            return YES;
        }
    }
    return NO;
}

- (void)ioFrameChannel:(Lookin_PTChannel *)channel didReceiveFrameOfType:(uint32_t)type tag:(uint32_t)tag payload:(Lookin_PTData *)payload {
    LKCLIConnectionRequest *matchedRequest = nil;
    NSMutableSet<LKCLIConnectionRequest *> *activeRequests = [self activeRequestsForChannel:channel createIfNeeded:NO];
    for (LKCLIConnectionRequest *request in activeRequests) {
        if (request.type == type && request.tag == tag) {
            matchedRequest = request;
            break;
        }
    }
    if (!matchedRequest) {
        return;
    }

    NSData *data = [NSData dataWithContentsOfDispatchData:payload.dispatchData];
    NSError *unarchiveError = nil;
    LookinConnectionResponseAttachment *attachment = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSObject class] fromData:data error:&unarchiveError];
    if (unarchiveError) {
        if (matchedRequest.failBlock) {
            matchedRequest.failBlock(unarchiveError);
        }
        [activeRequests removeObject:matchedRequest];
        return;
    }

    if (attachment.appIsInBackground) {
        [matchedRequest endTimeoutCount];
        [activeRequests removeObject:matchedRequest];
        if (matchedRequest.failBlock) {
            matchedRequest.failBlock([NSError errorWithDomain:LookinErrorDomain
                                                         code:LookinErrCode_PingFailForBackgroundState
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Target app is in background."}]);
        }
        return;
    }

    if (matchedRequest.succBlock) {
        matchedRequest.succBlock(attachment);
    }

    BOOL hasReceivedAllResponses = NO;
    if (attachment.dataTotalCount > 0) {
        matchedRequest.receivedDataCount += attachment.currentDataCount;
        hasReceivedAllResponses = (matchedRequest.receivedDataCount >= attachment.dataTotalCount);
    } else {
        hasReceivedAllResponses = YES;
    }

    if (hasReceivedAllResponses) {
        [matchedRequest endTimeoutCount];
        [activeRequests removeObject:matchedRequest];
        if (matchedRequest.completionBlock) {
            matchedRequest.completionBlock();
        }
    } else {
        [matchedRequest resetTimeoutCount];
    }
}

- (void)ioFrameChannel:(Lookin_PTChannel *)channel didEndWithError:(NSError *)error {
    LKCLIConnectionPort *port = [self.portsByChannel objectForKey:channel];
    if (port.connectedChannel == channel) {
        port.connectedChannel = nil;
    }
    [[self activeRequestsForChannel:channel createIfNeeded:NO] removeAllObjects];
    [channel close];
}

@end
