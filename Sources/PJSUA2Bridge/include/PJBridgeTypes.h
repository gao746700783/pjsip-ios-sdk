#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const PJBridgeErrorDomain;

typedef NS_ENUM(NSInteger, PJBridgeTransportType) {
    PJBridgeTransportTypeUDP = 0,
    PJBridgeTransportTypeTCP = 1,
    PJBridgeTransportTypeTLS = 2
};

typedef NS_ENUM(NSInteger, PJBridgeSRTPMode) {
    PJBridgeSRTPModeDisabled = 0,
    PJBridgeSRTPModeOptional = 1,
    PJBridgeSRTPModeMandatory = 2
};

typedef NS_ENUM(NSInteger, PJBridgeCallState) {
    PJBridgeCallStateNull = 0,
    PJBridgeCallStateCalling = 1,
    PJBridgeCallStateIncoming = 2,
    PJBridgeCallStateEarly = 3,
    PJBridgeCallStateConnecting = 4,
    PJBridgeCallStateConfirmed = 5,
    PJBridgeCallStateDisconnected = 6
};

typedef NS_ENUM(NSInteger, PJBridgeMediaState) {
    PJBridgeMediaStateNone = 0,
    PJBridgeMediaStateActive = 1,
    PJBridgeMediaStateLocalHold = 2,
    PJBridgeMediaStateRemoteHold = 3,
    PJBridgeMediaStateError = 4
};

typedef NS_ENUM(NSInteger, PJBridgeLogLevel) {
    PJBridgeLogLevelFatal = 0,
    PJBridgeLogLevelError = 1,
    PJBridgeLogLevelWarning = 2,
    PJBridgeLogLevelInfo = 3,
    PJBridgeLogLevelDebug = 4,
    PJBridgeLogLevelTrace = 5
};

typedef NS_ENUM(NSInteger, PJBridgeVideoOrientation) {
    PJBridgeVideoOrientationNatural = 0,
    PJBridgeVideoOrientationRotate90 = 1,
    PJBridgeVideoOrientationRotate180 = 2,
    PJBridgeVideoOrientationRotate270 = 3
};

@interface PJBridgeVideoCodecParam : NSObject
@property (nonatomic, copy) NSString *codecId;
@property (nonatomic, assign) uint8_t priority;
@property (nonatomic, assign) uint32_t width;
@property (nonatomic, assign) uint32_t height;
@property (nonatomic, assign) uint32_t fps;
@property (nonatomic, assign) uint32_t avgBitrateBps;
@property (nonatomic, assign) uint32_t maxBitrateBps;
@property (nonatomic, copy, nullable) NSString *packetizationMode;
@end

@interface PJBridgeEndpointConfig : NSObject
@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic, assign) NSUInteger maxCalls;
@property (nonatomic, assign) NSUInteger threadCount;
@property (nonatomic, assign) uint32_t clockRate;
@property (nonatomic, assign) uint32_t echoCancellationTailMs;
@property (nonatomic, assign) BOOL disableVAD;
@property (nonatomic, assign) BOOL enableVideo;
@property (nonatomic, assign) BOOL suspendAudioDeviceOnStart;
@property (nonatomic, strong, nullable) PJBridgeVideoCodecParam *preferredVideoCodec;
@property (nonatomic, assign) BOOL verifySipServerCert;
@property (nonatomic, copy, nullable) NSString *caListFilePath;
@property (nonatomic, assign) BOOL enableDnsSrvLookup;
@property (nonatomic, copy) NSArray<NSString *> *dnsServers;
@property (nonatomic, assign) BOOL enableSipLogging;
@property (nonatomic, assign) PJBridgeLogLevel sipLogLevel;
@property (nonatomic, assign) uint16_t localUDPPort;
@property (nonatomic, assign) uint16_t localTCPPort;
@property (nonatomic, assign) uint16_t localTLSPort;
@end

@interface PJBridgeAccountConfig : NSObject
@property (nonatomic, copy) NSString *accountIdURI;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *realm;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *srvDomain;
@property (nonatomic, assign) PJBridgeTransportType transport;
@property (nonatomic, assign) PJBridgeSRTPMode srtpMode;
@property (nonatomic, assign) BOOL srtpSecureSignaling;
@property (nonatomic, assign) uint32_t regTimeoutSec;
@property (nonatomic, assign) uint32_t regRetryIntervalSec;
@property (nonatomic, assign) BOOL enableICE;
@property (nonatomic, assign) BOOL enableVideoAutoShow;
@property (nonatomic, assign) BOOL enableVideoAutoTransmit;
@property (nonatomic, copy) NSArray<NSString *> *proxies;
@end

@interface PJBridgeCallInfo : NSObject
@property (nonatomic, assign) int32_t callId;
@property (nonatomic, copy) NSString *accountIdURI;
@property (nonatomic, copy) NSString *sipCallId;
@property (nonatomic, copy) NSString *remoteURI;
@property (nonatomic, copy) NSString *remoteContact;
@property (nonatomic, assign) PJBridgeCallState state;
@property (nonatomic, copy) NSString *stateText;
@property (nonatomic, assign) int32_t lastStatusCode;
@property (nonatomic, copy) NSString *lastReason;
@property (nonatomic, assign) NSTimeInterval connectDuration;
@property (nonatomic, assign) NSTimeInterval totalDuration;
@property (nonatomic, assign) BOOL isVideo;
@property (nonatomic, assign) BOOL isLocalHold;
@property (nonatomic, assign) BOOL isLocalMuted;
@property (nonatomic, assign) BOOL isVideoMuted;
@end

@interface PJBridgeCallStats : NSObject
@property (nonatomic, assign) int32_t callId;
@property (nonatomic, copy) NSString *accountIdURI;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) NSString *audioCodec;
@property (nonatomic, assign) int32_t callStatusCode;
@property (nonatomic, assign) uint32_t rxPackets;
@property (nonatomic, assign) uint32_t txPackets;
@property (nonatomic, assign) uint32_t rxPacketLoss;
@property (nonatomic, assign) uint32_t txPacketLoss;
@property (nonatomic, assign) double rttMeanMs;
@property (nonatomic, assign) double rxJitterMeanMs;
@property (nonatomic, assign) double txJitterMeanMs;
@end

@interface PJBridgeCodecPriority : NSObject
@property (nonatomic, copy) NSString *codecId;
@property (nonatomic, assign) uint8_t priority;
- (instancetype)initWithCodecId:(NSString *)codecId priority:(uint8_t)priority;
@end

NS_ASSUME_NONNULL_END
