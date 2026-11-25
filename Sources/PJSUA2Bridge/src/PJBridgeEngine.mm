#import "PJBridgeEngine.h"
#import "PJCppWrappers.hpp"

#include <memory>
#include <unordered_map>

using namespace pjsipios;

@interface PJBridgeEngine () {
    std::unique_ptr<pj::Endpoint> _endpoint;
    std::unique_ptr<PJLogWriter> _logWriter;
    std::unordered_map<std::string, std::shared_ptr<PJAccount>> _accounts;
    pj::TransportId _udpTransportId;
    pj::TransportId _tcpTransportId;
    pj::TransportId _tlsTransportId;
    BOOL _started;
    BOOL _dnsSrvEnabled;
}
@end

@implementation PJBridgeEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _udpTransportId = PJSUA_INVALID_ID;
        _tcpTransportId = PJSUA_INVALID_ID;
        _tlsTransportId = PJSUA_INVALID_ID;
        _started = NO;
        _dnsSrvEnabled = NO;
    }
    return self;
}

- (void)dealloc {
    if (_started) {
        [self stopWithError:nil];
    }
}

- (BOOL)isStarted {
    return _started;
}

- (BOOL)registerCurrentThreadWithName:(NSString *)name error:(NSError * _Nullable * _Nullable)error {
    if (!_endpoint) {
        return YES;
    }
    try {
        if (!_endpoint->libIsThreadRegistered()) {
            _endpoint->libRegisterThread(StdStringFromNSString(name));
        }
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

#pragma mark - Lifecycle

- (BOOL)startWithConfig:(PJBridgeEndpointConfig *)config error:(NSError * _Nullable * _Nullable)error {
    if (_started) {
        return YES;
    }

    try {
        _endpoint = std::make_unique<pj::Endpoint>();
        _endpoint->libCreate();

        pj::EpConfig epConfig;
        epConfig.uaConfig.maxCalls = (unsigned)config.maxCalls;
        epConfig.uaConfig.threadCnt = (unsigned)config.threadCount;
        epConfig.uaConfig.userAgent = StdStringFromNSString(config.userAgent);

        _dnsSrvEnabled = config.enableDnsSrvLookup;
        if (config.enableDnsSrvLookup && config.dnsServers.count > 0) {
            for (NSString *dns in config.dnsServers) {
                epConfig.uaConfig.nameserver.push_back(StdStringFromNSString(dns));
            }
        }

        epConfig.medConfig.clockRate = config.clockRate;
        epConfig.medConfig.ecTailLen = config.echoCancellationTailMs;
        epConfig.medConfig.noVad = config.disableVAD ? true : false;
        epConfig.medConfig.vidPreviewEnableNative = config.enableVideo ? true : false;

        if (config.enableSipLogging) {
            _logWriter = std::make_unique<PJLogWriter>(self.delegate);
            epConfig.logConfig.level = (unsigned)config.sipLogLevel;
            epConfig.logConfig.consoleLevel = (unsigned)config.sipLogLevel;
            epConfig.logConfig.writer = _logWriter.get();
        } else {
            epConfig.logConfig.level = 1;
            epConfig.logConfig.consoleLevel = 0;
        }

        _endpoint->libInit(epConfig);

        // Create UDP transport
        pj::TransportConfig udpCfg;
        udpCfg.port = config.localUDPPort;
        _udpTransportId = _endpoint->transportCreate(PJSIP_TRANSPORT_UDP, udpCfg);

        // Create TCP transport
        pj::TransportConfig tcpCfg;
        tcpCfg.port = config.localTCPPort;
        _tcpTransportId = _endpoint->transportCreate(PJSIP_TRANSPORT_TCP, tcpCfg);

        // Create TLS transport (uses Apple Darwin SSL in swift-pjsip)
        try {
            pj::TransportConfig tlsCfg;
            tlsCfg.port = config.localTLSPort;
            tlsCfg.tlsConfig.verifyServer = config.verifySipServerCert ? true : false;
            if (config.caListFilePath.length > 0) {
                tlsCfg.tlsConfig.CaListFile = StdStringFromNSString(config.caListFilePath);
            }
            _tlsTransportId = _endpoint->transportCreate(PJSIP_TRANSPORT_TLS, tlsCfg);
        } catch (const pj::Error &) {
            _tlsTransportId = PJSUA_INVALID_ID;
        }

        _endpoint->libStart();
        _started = YES;

        // Suspend CoreAudio device until CallKit or the app activates audio.
        if (config.suspendAudioDeviceOnStart) {
            try {
                _endpoint->audDevManager().setNullDev();
            } catch (const pj::Error &) {
            }
        }

        // Apply preferred video codec priority and H.264/VP8 encoder tuning if configured.
        if (config.enableVideo && config.preferredVideoCodec != nil) {
            [self setVideoCodecParam:config.preferredVideoCodec error:nil];
        }

        id<PJBridgeDelegate> strongDelegate = self.delegate;
        if (strongDelegate) {
            [strongDelegate bridgeDidChangeStackStatus:YES];
        }
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        [self cleanupEndpoint];
        return NO;
    }
}

- (BOOL)stopWithError:(NSError * _Nullable * _Nullable)error {
    if (!_started || !_endpoint) {
        return YES;
    }
    try {
        _endpoint->hangupAllCalls();
        _accounts.clear();
        _endpoint->libDestroy();
        [self cleanupEndpoint];

        id<PJBridgeDelegate> strongDelegate = self.delegate;
        if (strongDelegate) {
            [strongDelegate bridgeDidChangeStackStatus:NO];
        }
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        [self cleanupEndpoint];
        return NO;
    }
}

- (void)cleanupEndpoint {
    _accounts.clear();
    _endpoint.reset();
    _logWriter.reset();
    _udpTransportId = PJSUA_INVALID_ID;
    _tcpTransportId = PJSUA_INVALID_ID;
    _tlsTransportId = PJSUA_INVALID_ID;
    _started = NO;
}

- (BOOL)handleIPChangeWithError:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) {
        return NO;
    }
    try {
        pj::IpChangeParam param;
        param.restartListener = true;
        param.restartLisDelay = 0;
        _endpoint->handleIpChange(param);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

#pragma mark - Accounts

- (pj::TransportId)transportIdForType:(PJBridgeTransportType)type {
    switch (type) {
        case PJBridgeTransportTypeUDP: return _udpTransportId;
        case PJBridgeTransportTypeTCP: return _tcpTransportId;
        case PJBridgeTransportTypeTLS: return _tlsTransportId;
    }
}

- (NSString *)transportParamForType:(PJBridgeTransportType)type {
    switch (type) {
        case PJBridgeTransportTypeUDP: return @"";
        case PJBridgeTransportTypeTCP: return @";transport=tcp";
        case PJBridgeTransportTypeTLS: return @";transport=tls";
    }
}

- (pj::AccountConfig)buildAccountConfig:(PJBridgeAccountConfig *)cfg {
    pj::AccountConfig accCfg;
    NSString *scheme = (cfg.transport == PJBridgeTransportTypeTLS) ? @"sips" : @"sip";
    NSString *transportParam = [self transportParamForType:cfg.transport];

    NSString *idUri = cfg.accountIdURI.length > 0
        ? cfg.accountIdURI
        : [NSString stringWithFormat:@"%@:%@@%@", scheme, cfg.username, cfg.host];

    if (cfg.displayName.length > 0) {
        accCfg.idUri = StdStringFromNSString([NSString stringWithFormat:@"\"%@\" <%@>", cfg.displayName, idUri]);
    } else {
        accCfg.idUri = StdStringFromNSString(idUri);
    }

    NSString *registrarHost = (cfg.srvDomain.length > 0) ? cfg.srvDomain : cfg.host;
    NSString *registrarUri = nil;
    if (_dnsSrvEnabled && cfg.port == 0) {
        registrarUri = [NSString stringWithFormat:@"%@:%@%@", scheme, registrarHost, transportParam];
    } else {
        uint16_t effectivePort = cfg.port > 0 ? cfg.port : (cfg.transport == PJBridgeTransportTypeTLS ? 5061 : 5060);
        registrarUri = [NSString stringWithFormat:@"%@:%@:%u%@", scheme, registrarHost, effectivePort, transportParam];
    }

    accCfg.regConfig.registrarUri = StdStringFromNSString(registrarUri);
    accCfg.regConfig.timeoutSec = cfg.regTimeoutSec;
    accCfg.regConfig.retryIntervalSec = cfg.regRetryIntervalSec;
    accCfg.regConfig.registerOnAdd = true;

    pj::AuthCredInfo cred("digest",
                          StdStringFromNSString(cfg.realm.length > 0 ? cfg.realm : @"*"),
                          StdStringFromNSString(cfg.username),
                          0,
                          StdStringFromNSString(cfg.password));
    accCfg.sipConfig.authCreds.push_back(cred);

    pj::TransportId tid = [self transportIdForType:cfg.transport];
    if (tid != PJSUA_INVALID_ID) {
        accCfg.sipConfig.transportId = tid;
    }

    for (NSString *proxy in cfg.proxies) {
        accCfg.sipConfig.proxies.push_back(StdStringFromNSString(proxy));
    }

    switch (cfg.srtpMode) {
        case PJBridgeSRTPModeDisabled:
            accCfg.mediaConfig.srtpUse = PJMEDIA_SRTP_DISABLED;
            break;
        case PJBridgeSRTPModeOptional:
            accCfg.mediaConfig.srtpUse = PJMEDIA_SRTP_OPTIONAL;
            break;
        case PJBridgeSRTPModeMandatory:
            accCfg.mediaConfig.srtpUse = PJMEDIA_SRTP_MANDATORY;
            break;
    }
    accCfg.mediaConfig.srtpSecureSignaling = cfg.srtpSecureSignaling ? 1 : 0;

    accCfg.natConfig.iceEnabled = cfg.enableICE ? true : false;
    accCfg.natConfig.contactRewriteUse = 1;
    accCfg.natConfig.viaRewriteUse = 1;
    accCfg.natConfig.sdpNatRewriteUse = 1;

    accCfg.videoConfig.autoShowIncoming = cfg.enableVideoAutoShow ? true : false;
    accCfg.videoConfig.autoTransmitOutgoing = cfg.enableVideoAutoTransmit ? true : false;

    return accCfg;
}

- (BOOL)addOrUpdateAccount:(PJBridgeAccountConfig *)config error:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) {
        return NO;
    }
    try {
        std::string key = StdStringFromNSString(config.accountIdURI);
        pj::AccountConfig accCfg = [self buildAccountConfig:config];

        auto it = _accounts.find(key);
        if (it != _accounts.end()) {
            it->second->modify(accCfg);
        } else {
            auto account = std::make_shared<PJAccount>(key, self.delegate);
            account->create(accCfg, _accounts.empty());
            _accounts[key] = std::move(account);
        }
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)removeAccount:(NSString *)accountIdURI error:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) {
        return NO;
    }
    try {
        std::string key = StdStringFromNSString(accountIdURI);
        auto it = _accounts.find(key);
        if (it != _accounts.end()) {
            it->second->hangupAllCalls();
            it->second->shutdown();
            _accounts.erase(it);
        }
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)setRegistration:(BOOL)renew forAccount:(NSString *)accountIdURI error:(NSError * _Nullable * _Nullable)error {
    auto account = [self findAccount:accountIdURI error:error];
    if (!account) {
        return NO;
    }
    try {
        account->setRegistration(renew ? true : false);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

#pragma mark - Calls

- (int32_t)makeCallFromAccount:(NSString *)accountIdURI
                   destination:(NSString *)destinationURI
                       isVideo:(BOOL)isVideo
               isVideoMuteInit:(BOOL)isVideoMuteInit
                  isSilentCall:(BOOL)isSilentCall
                 customHeaders:(nullable NSDictionary<NSString *, NSString *> *)customHeaders
                  fixedCallId:(nullable NSString *)fixedCallId
                         error:(NSError * _Nullable * _Nullable)error {
    auto account = [self findAccount:accountIdURI error:error];
    if (!account) {
        return -1;
    }

    try {
        auto call = account->createOutgoingCall();
        call->setSilentCall(isSilentCall ? true : false);

        pj::CallOpParam prm(true);
        prm.opt.audioCount = 1;
        prm.opt.videoCount = isVideo ? 1 : 0;

        if (customHeaders.count > 0) {
            for (NSString *headerName in customHeaders) {
                pj::SipHeader hdr;
                hdr.hName = StdStringFromNSString(headerName);
                hdr.hValue = StdStringFromNSString(customHeaders[headerName]);
                prm.txOption.headers.push_back(hdr);
            }
        }
        if (fixedCallId.length > 0) {
            pj::SipHeader callIdHdr;
            callIdHdr.hName = "Call-ID";
            callIdHdr.hValue = StdStringFromNSString(fixedCallId);
            prm.txOption.headers.push_back(callIdHdr);
        }

        call->makeCall(StdStringFromNSString(destinationURI), prm);
        int callId = call->getId();
        account->registerCall(callId, call);

        if (isVideo && isVideoMuteInit) {
            try {
                call->setVideoMute(true);
            } catch (const pj::Error &) {
            }
        }
        return callId;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return -1;
    }
}

- (int32_t)makeDirectCallTo:(NSString *)destinationURI
                  transport:(PJBridgeTransportType)transport
                    isVideo:(BOOL)isVideo
              customHeaders:(nullable NSDictionary<NSString *, NSString *> *)customHeaders
                      error:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) {
        return -1;
    }
    NSString *directKey = @"sip:direct@local";
    if (_accounts.find(StdStringFromNSString(directKey)) == _accounts.end()) {
        try {
            pj::AccountConfig accCfg;
            accCfg.idUri = StdStringFromNSString(directKey);
            accCfg.regConfig.registerOnAdd = false;
            pj::TransportId tid = [self transportIdForType:transport];
            if (tid != PJSUA_INVALID_ID) {
                accCfg.sipConfig.transportId = tid;
            }
            auto account = std::make_shared<PJAccount>(StdStringFromNSString(directKey), self.delegate);
            account->create(accCfg, false);
            _accounts[StdStringFromNSString(directKey)] = std::move(account);
        } catch (const pj::Error &err) {
            if (error) *error = NSErrorFromPJError(err);
            return -1;
        }
    }
    return [self makeCallFromAccount:directKey
                         destination:destinationURI
                             isVideo:isVideo
                     isVideoMuteInit:NO
                        isSilentCall:NO
                       customHeaders:customHeaders
                        fixedCallId:nil
                               error:error];
}

- (BOOL)answerCall:(int32_t)callId
         inAccount:(NSString *)accountIdURI
           isVideo:(BOOL)isVideo
   isVideoMuteInit:(BOOL)isVideoMuteInit
             error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        pj::CallOpParam prm(true);
        prm.statusCode = PJSIP_SC_OK;
        prm.opt.audioCount = 1;
        prm.opt.videoCount = isVideo ? 1 : 0;
        call->answer(prm);
        if (isVideo && isVideoMuteInit) {
            try {
                call->setVideoMute(true);
            } catch (const pj::Error &) {
            }
        }
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)declineCall:(int32_t)callId
          inAccount:(NSString *)accountIdURI
         statusCode:(int32_t)statusCode
              error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        pj::CallOpParam prm;
        prm.statusCode = (pjsip_status_code)(statusCode > 0 ? statusCode : PJSIP_SC_DECLINE);
        call->hangup(prm);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)hangupCall:(int32_t)callId
         inAccount:(NSString *)accountIdURI
             error:(NSError * _Nullable * _Nullable)error {
    return [self declineCall:callId inAccount:accountIdURI statusCode:PJSIP_SC_DECLINE error:error];
}

- (BOOL)hangupAllCallsWithError:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) return NO;
    try {
        _endpoint->hangupAllCalls();
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)setMute:(BOOL)muted
        forCall:(int32_t)callId
      inAccount:(NSString *)accountIdURI
          error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        call->setLocalMute(muted ? true : false);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)setHold:(BOOL)hold
        forCall:(int32_t)callId
      inAccount:(NSString *)accountIdURI
          error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        call->setLocalHold(hold ? true : false);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)holdAllCallsWithError:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) return NO;
    for (auto &kv : _accounts) {
        kv.second->holdAllCalls();
    }
    return YES;
}

- (BOOL)reconnectCall:(int32_t)callId
            inAccount:(NSString *)accountIdURI
                error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        pj::CallOpParam prm(true);
        prm.opt.flag |= PJSUA_CALL_REINIT_MEDIA | PJSUA_CALL_UPDATE_CONTACT | PJSUA_CALL_UPDATE_VIA;
        call->reinvite(prm);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)blindTransferCall:(int32_t)callId
                inAccount:(NSString *)accountIdURI
            toDestination:(NSString *)destinationURI
                    error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        pj::CallOpParam prm;
        call->xfer(StdStringFromNSString(destinationURI), prm);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)attendedTransferCall:(int32_t)callId
                   inAccount:(NSString *)accountIdURI
           toTargetCallId:(int32_t)targetCallId
                       error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    auto targetCall = [self findCall:targetCallId inAccount:accountIdURI error:error];
    if (!call || !targetCall) return NO;
    try {
        pj::CallOpParam prm;
        call->xferReplaces(*targetCall, prm);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)sendDTMF:(NSString *)digits
         forCall:(int32_t)callId
       inAccount:(NSString *)accountIdURI
           error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        pj::CallSendDtmfParam prm;
        prm.method = PJSUA_DTMF_METHOD_RFC2833;
        prm.digits = StdStringFromNSString(digits);
        call->sendDtmf(prm);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

#pragma mark - Video Control, Codec Tuning & Orientation

- (BOOL)setVideoMute:(BOOL)muted
             forCall:(int32_t)callId
           inAccount:(NSString *)accountIdURI
               error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        call->setVideoMute(muted ? true : false);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)switchCameraForCall:(int32_t)callId
                  inAccount:(NSString *)accountIdURI
                      error:(NSError * _Nullable * _Nullable)error {
    auto call = [self findCall:callId inAccount:accountIdURI error:error];
    if (!call) return NO;
    try {
        call->switchCamera();
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)setVideoCodecParam:(PJBridgeVideoCodecParam *)param
                     error:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) return NO;
    try {
        std::string codecId = StdStringFromNSString(param.codecId);
        _endpoint->videoCodecSetPriority(codecId, param.priority);

        pj::VidCodecParam vcp = _endpoint->getVideoCodecParam(codecId);
        if (param.width > 0 && param.height > 0) {
            vcp.encFmt.width = param.width;
            vcp.encFmt.height = param.height;
        }
        if (param.fps > 0) {
            vcp.encFmt.fpsNum = param.fps;
            vcp.encFmt.fpsDenum = 1;
        }
        if (param.avgBitrateBps > 0) {
            vcp.encFmt.avgBps = param.avgBitrateBps;
        }
        if (param.maxBitrateBps > 0) {
            vcp.encFmt.maxBps = param.maxBitrateBps;
        }
        if (param.packetizationMode.length > 0) {
            std::string modeVal = StdStringFromNSString(param.packetizationMode);
            bool updated = false;
            for (auto &fp : vcp.encFmtp) {
                if (fp.name == "packetization-mode") {
                    fp.val = modeVal;
                    updated = true;
                    break;
                }
            }
            if (!updated) {
                pj::CodecFmtp fp;
                fp.name = "packetization-mode";
                fp.val = modeVal;
                vcp.encFmtp.push_back(fp);
            }
        }
        _endpoint->setVideoCodecParam(codecId, vcp);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (BOOL)setVideoCaptureOrientation:(PJBridgeVideoOrientation)orientation
                   captureDeviceId:(int32_t)deviceId
                             error:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) return NO;
    try {
        int effectiveDev = (deviceId >= 0) ? deviceId : PJMEDIA_VID_DEFAULT_CAPTURE_DEV;
        _endpoint->vidDevManager().setCaptureOrient(effectiveDev, MediaOrientFromBridge(orientation), true);
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

- (nullable PJBridgeCallInfo *)callInfoForCall:(int32_t)callId
                                     inAccount:(NSString *)accountIdURI {
    auto call = [self findCall:callId inAccount:accountIdURI error:nil];
    if (!call) return nil;
    return call->snapshotCallInfo();
}

#pragma mark - Audio Device (CallKit Handoff)

- (BOOL)setAudioDeviceActive:(BOOL)active error:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) return NO;
    try {
        pj::AudDevManager &mgr = _endpoint->audDevManager();
        if (active) {
            mgr.setCaptureDev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV);
            mgr.setPlaybackDev(PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
        } else {
            mgr.setNullDev();
        }
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

#pragma mark - Codecs

- (nullable NSArray<PJBridgeCodecPriority *> *)codecPrioritiesWithError:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) return nil;
    try {
        pj::CodecInfoVector2 codecs = _endpoint->codecEnum2();
        NSMutableArray<PJBridgeCodecPriority *> *result = [NSMutableArray arrayWithCapacity:codecs.size()];
        for (const auto &c : codecs) {
            PJBridgeCodecPriority *item = [[PJBridgeCodecPriority alloc] initWithCodecId:NSStringFromStdString(c.codecId)
                                                                                priority:c.priority];
            [result addObject:item];
        }
        return result;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return nil;
    }
}

- (BOOL)setCodecPriorities:(NSArray<PJBridgeCodecPriority *> *)priorities error:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) return NO;
    try {
        for (PJBridgeCodecPriority *item in priorities) {
            _endpoint->codecSetPriority(StdStringFromNSString(item.codecId), item.priority);
        }
        return YES;
    } catch (const pj::Error &err) {
        if (error) *error = NSErrorFromPJError(err);
        return NO;
    }
}

#pragma mark - Helpers

- (BOOL)ensureStartedWithError:(NSError * _Nullable * _Nullable)error {
    if (_started && _endpoint) {
        return YES;
    }
    if (error) {
        *error = [NSError errorWithDomain:PJBridgeErrorDomain
                                     code:-1001
                                 userInfo:@{NSLocalizedDescriptionKey: @"SIP stack is not started."}];
    }
    return NO;
}

- (std::shared_ptr<PJAccount>)findAccount:(NSString *)accountIdURI error:(NSError * _Nullable * _Nullable)error {
    if (![self ensureStartedWithError:error]) {
        return nullptr;
    }
    auto it = _accounts.find(StdStringFromNSString(accountIdURI));
    if (it == _accounts.end()) {
        if (error) {
            *error = [NSError errorWithDomain:PJBridgeErrorDomain
                                         code:-1002
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Account not found: %@", accountIdURI]}];
        }
        return nullptr;
    }
    return it->second;
}

- (std::shared_ptr<PJCall>)findCall:(int32_t)callId
                          inAccount:(NSString *)accountIdURI
                              error:(NSError * _Nullable * _Nullable)error {
    auto account = [self findAccount:accountIdURI error:error];
    if (!account) {
        return nullptr;
    }
    auto call = account->findCall(callId);
    if (!call) {
        if (error) {
            *error = [NSError errorWithDomain:PJBridgeErrorDomain
                                         code:-1003
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Call %d not found in account %@", callId, accountIdURI]}];
        }
        return nullptr;
    }
    return call;
}

@end
