#import "PJBridgeTypes.h"

NSErrorDomain const PJBridgeErrorDomain = @"com.pjsipios.bridge.error";

@implementation PJBridgeVideoCodecParam
- (instancetype)init {
    self = [super init];
    if (self) {
        _codecId = @"H264/97";
        _priority = 255;
        _width = 640;
        _height = 480;
        _fps = 15;
        _avgBitrateBps = 512000;
        _maxBitrateBps = 1024000;
        _packetizationMode = @"1";
    }
    return self;
}
@end

@implementation PJBridgeEndpointConfig
- (instancetype)init {
    self = [super init];
    if (self) {
        _userAgent = @"PJSIPiOS/1.0";
        _maxCalls = 4;
        _threadCount = 1;
        _clockRate = 16000;
        _echoCancellationTailMs = 100;
        _disableVAD = YES;
        _enableVideo = YES;
        _suspendAudioDeviceOnStart = YES;
        _verifySipServerCert = NO;
        _enableDnsSrvLookup = NO;
        _dnsServers = @[];
        _enableSipLogging = NO;
        _sipLogLevel = PJBridgeLogLevelInfo;
        _localUDPPort = 0;
        _localTCPPort = 0;
        _localTLSPort = 0;
    }
    return self;
}
@end

@implementation PJBridgeAccountConfig
- (instancetype)init {
    self = [super init];
    if (self) {
        _accountIdURI = @"";
        _host = @"";
        _port = 5060;
        _username = @"";
        _password = @"";
        _realm = @"*";
        _transport = PJBridgeTransportTypeUDP;
        _srtpMode = PJBridgeSRTPModeDisabled;
        _srtpSecureSignaling = NO;
        _regTimeoutSec = 300;
        _regRetryIntervalSec = 60;
        _enableICE = NO;
        _enableVideoAutoShow = YES;
        _enableVideoAutoTransmit = NO;
        _proxies = @[];
    }
    return self;
}
@end

@implementation PJBridgeCallInfo
- (instancetype)init {
    self = [super init];
    if (self) {
        _callId = -1;
        _accountIdURI = @"";
        _sipCallId = @"";
        _remoteURI = @"";
        _remoteContact = @"";
        _state = PJBridgeCallStateNull;
        _stateText = @"NULL";
        _lastStatusCode = 0;
        _lastReason = @"";
    }
    return self;
}
@end

@implementation PJBridgeCallStats
- (instancetype)init {
    self = [super init];
    if (self) {
        _callId = -1;
        _accountIdURI = @"";
        _audioCodec = @"";
    }
    return self;
}
@end

@implementation PJBridgeCodecPriority
- (instancetype)initWithCodecId:(NSString *)codecId priority:(uint8_t)priority {
    self = [super init];
    if (self) {
        _codecId = [codecId copy];
        _priority = priority;
    }
    return self;
}
@end
