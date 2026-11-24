#import <Foundation/Foundation.h>
#import "PJBridgeTypes.h"
#import "PJBridgeDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/// Objective-C++ facade over PJSUA2 (pj::Endpoint, pj::Account, pj::Call).
/// All mutating and query methods must be called on a PJLIB-registered thread
/// (enforced by SipWorkerThread in the Swift layer).
@interface PJBridgeEngine : NSObject

@property (nonatomic, weak, nullable) id<PJBridgeDelegate> delegate;
@property (nonatomic, readonly) BOOL isStarted;

/// Registers the current POSIX thread with PJLIB if not already registered.
- (BOOL)registerCurrentThreadWithName:(NSString *)name error:(NSError * _Nullable * _Nullable)error;

/// Lifecycle
- (BOOL)startWithConfig:(PJBridgeEndpointConfig *)config error:(NSError * _Nullable * _Nullable)error;
- (BOOL)stopWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)handleIPChangeWithError:(NSError * _Nullable * _Nullable)error;

/// Account management
- (BOOL)addOrUpdateAccount:(PJBridgeAccountConfig *)config error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removeAccount:(NSString *)accountIdURI error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setRegistration:(BOOL)renew forAccount:(NSString *)accountIdURI error:(NSError * _Nullable * _Nullable)error;

/// Call initiation
- (int32_t)makeCallFromAccount:(NSString *)accountIdURI
                   destination:(NSString *)destinationURI
                       isVideo:(BOOL)isVideo
               isVideoMuteInit:(BOOL)isVideoMuteInit
                  isSilentCall:(BOOL)isSilentCall
                 customHeaders:(nullable NSDictionary<NSString *, NSString *> *)customHeaders
                  fixedCallId:(nullable NSString *)fixedCallId
                         error:(NSError * _Nullable * _Nullable)error;

- (int32_t)makeDirectCallTo:(NSString *)destinationURI
                  transport:(PJBridgeTransportType)transport
                    isVideo:(BOOL)isVideo
              customHeaders:(nullable NSDictionary<NSString *, NSString *> *)customHeaders
                      error:(NSError * _Nullable * _Nullable)error;

/// Call control
- (BOOL)answerCall:(int32_t)callId
         inAccount:(NSString *)accountIdURI
           isVideo:(BOOL)isVideo
   isVideoMuteInit:(BOOL)isVideoMuteInit
             error:(NSError * _Nullable * _Nullable)error;

- (BOOL)declineCall:(int32_t)callId
          inAccount:(NSString *)accountIdURI
         statusCode:(int32_t)statusCode
              error:(NSError * _Nullable * _Nullable)error;

- (BOOL)hangupCall:(int32_t)callId
         inAccount:(NSString *)accountIdURI
             error:(NSError * _Nullable * _Nullable)error;

- (BOOL)hangupAllCallsWithError:(NSError * _Nullable * _Nullable)error;

- (BOOL)setMute:(BOOL)muted
        forCall:(int32_t)callId
      inAccount:(NSString *)accountIdURI
          error:(NSError * _Nullable * _Nullable)error;

- (BOOL)setHold:(BOOL)hold
        forCall:(int32_t)callId
      inAccount:(NSString *)accountIdURI
          error:(NSError * _Nullable * _Nullable)error;

- (BOOL)holdAllCallsWithError:(NSError * _Nullable * _Nullable)error;

- (BOOL)reconnectCall:(int32_t)callId
            inAccount:(NSString *)accountIdURI
                error:(NSError * _Nullable * _Nullable)error;

- (BOOL)blindTransferCall:(int32_t)callId
                inAccount:(NSString *)accountIdURI
            toDestination:(NSString *)destinationURI
                    error:(NSError * _Nullable * _Nullable)error;

- (BOOL)attendedTransferCall:(int32_t)callId
                   inAccount:(NSString *)accountIdURI
           toTargetCallId:(int32_t)targetCallId
                       error:(NSError * _Nullable * _Nullable)error;

- (BOOL)sendDTMF:(NSString *)digits
         forCall:(int32_t)callId
       inAccount:(NSString *)accountIdURI
           error:(NSError * _Nullable * _Nullable)error;

/// Video control, H.264 codec tuning, and camera orientation
- (BOOL)setVideoMute:(BOOL)muted
             forCall:(int32_t)callId
           inAccount:(NSString *)accountIdURI
               error:(NSError * _Nullable * _Nullable)error;

- (BOOL)switchCameraForCall:(int32_t)callId
                  inAccount:(NSString *)accountIdURI
                      error:(NSError * _Nullable * _Nullable)error;

- (BOOL)setVideoCodecParam:(PJBridgeVideoCodecParam *)param
                     error:(NSError * _Nullable * _Nullable)error;

- (BOOL)setVideoCaptureOrientation:(PJBridgeVideoOrientation)orientation
                   captureDeviceId:(int32_t)deviceId
                             error:(NSError * _Nullable * _Nullable)error;

/// Call query
- (nullable PJBridgeCallInfo *)callInfoForCall:(int32_t)callId
                                     inAccount:(NSString *)accountIdURI;

/// Audio device hooks for iOS CallKit / AVAudioSession handoff
- (BOOL)setAudioDeviceActive:(BOOL)active error:(NSError * _Nullable * _Nullable)error;

/// Codec priority management
- (nullable NSArray<PJBridgeCodecPriority *> *)codecPrioritiesWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)setCodecPriorities:(NSArray<PJBridgeCodecPriority *> *)priorities error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
