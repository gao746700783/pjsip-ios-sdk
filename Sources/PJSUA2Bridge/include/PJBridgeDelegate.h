#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "PJBridgeTypes.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PJBridgeDelegate <NSObject>

- (void)bridgeDidChangeStackStatus:(BOOL)started;

- (void)bridgeAccount:(NSString *)accountIdURI
  didChangeRegStatus:(int32_t)statusCode
              reason:(NSString *)reason
            isActive:(BOOL)isActive;

- (void)bridgeAccount:(NSString *)accountIdURI
   didReceiveCallInfo:(PJBridgeCallInfo *)callInfo;

- (void)bridgeAccount:(NSString *)accountIdURI
   didChangeCallState:(PJBridgeCallInfo *)callInfo;

- (void)bridgeAccount:(NSString *)accountIdURI
    didChangeMediaForCall:(int32_t)callId
              isLocalHold:(BOOL)isLocalHold
             isLocalMuted:(BOOL)isLocalMuted
             isVideoMuted:(BOOL)isVideoMuted
                  isVideo:(BOOL)isVideo;

/// Delivers native iOS UIView instances for local camera preview and remote video rendering.
- (void)bridgeAccount:(NSString *)accountIdURI
    didPrepareVideoForCall:(int32_t)callId
              localPreview:(nullable UIView *)localView
               remoteVideo:(nullable UIView *)remoteView;

- (void)bridgeAccount:(NSString *)accountIdURI
    didReceiveCallStats:(PJBridgeCallStats *)stats;

- (void)bridgeAccount:(NSString *)accountIdURI
    didReceiveDtmfDigit:(NSString *)digit
                forCall:(int32_t)callId;

- (void)bridgeAccount:(NSString *)accountIdURI
    didChangeTransferStatus:(int32_t)statusCode
                     reason:(NSString *)reason
                    isFinal:(BOOL)isFinal
                    forCall:(int32_t)callId;

- (void)bridgeDidReceiveLogMessage:(NSString *)message
                             level:(PJBridgeLogLevel)level;

@end

NS_ASSUME_NONNULL_END
