#import "PJCppWrappers.hpp"
#import <dispatch/dispatch.h>

namespace pjsipios {

NSError *NSErrorFromPJError(const pj::Error &err) {
    NSString *description = NSStringFromStdString(err.info(false));
    NSString *reason = NSStringFromStdString(err.reason);
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: description.length > 0 ? description : @"PJSUA2 error",
        NSLocalizedFailureReasonErrorKey: reason.length > 0 ? reason : @"Unknown PJSIP error",
        @"PJSIPTitle": NSStringFromStdString(err.title),
        @"PJSIPSourceFile": NSStringFromStdString(err.srcFile),
        @"PJSIPSourceLine": @(err.srcLine)
    };
    return [NSError errorWithDomain:PJBridgeErrorDomain code:(NSInteger)err.status userInfo:userInfo];
}

NSString *NSStringFromStdString(const std::string &str) {
    if (str.empty()) {
        return @"";
    }
    NSString *result = [NSString stringWithUTF8String:str.c_str()];
    return result ?: @"";
}

std::string StdStringFromNSString(NSString * _Nullable str) {
    if (!str || str.length == 0) {
        return std::string();
    }
    const char *utf8 = str.UTF8String;
    return utf8 ? std::string(utf8) : std::string();
}

PJBridgeCallState CallStateFromPJSIP(pjsip_inv_state state) {
    switch (state) {
        case PJSIP_INV_STATE_NULL:         return PJBridgeCallStateNull;
        case PJSIP_INV_STATE_CALLING:      return PJBridgeCallStateCalling;
        case PJSIP_INV_STATE_INCOMING:     return PJBridgeCallStateIncoming;
        case PJSIP_INV_STATE_EARLY:        return PJBridgeCallStateEarly;
        case PJSIP_INV_STATE_CONNECTING:   return PJBridgeCallStateConnecting;
        case PJSIP_INV_STATE_CONFIRMED:    return PJBridgeCallStateConfirmed;
        case PJSIP_INV_STATE_DISCONNECTED: return PJBridgeCallStateDisconnected;
        default:                           return PJBridgeCallStateNull;
    }
}

PJBridgeLogLevel LogLevelFromPJSIP(int level) {
    if (level <= 0) return PJBridgeLogLevelFatal;
    if (level == 1) return PJBridgeLogLevelError;
    if (level == 2) return PJBridgeLogLevelWarning;
    if (level == 3) return PJBridgeLogLevelInfo;
    if (level == 4) return PJBridgeLogLevelDebug;
    return PJBridgeLogLevelTrace;
}

pjmedia_orient MediaOrientFromBridge(PJBridgeVideoOrientation orient) {
    switch (orient) {
        case PJBridgeVideoOrientationNatural:   return PJMEDIA_ORIENT_NATURAL;
        case PJBridgeVideoOrientationRotate90:  return PJMEDIA_ORIENT_ROTATE_90DEG;
        case PJBridgeVideoOrientationRotate180: return PJMEDIA_ORIENT_ROTATE_180DEG;
        case PJBridgeVideoOrientationRotate270: return PJMEDIA_ORIENT_ROTATE_270DEG;
    }
}

#pragma mark - PJLogWriter

PJLogWriter::PJLogWriter(__weak id<PJBridgeDelegate> delegate)
    : delegate_(delegate) {}

void PJLogWriter::write(const pj::LogEntry &entry) {
    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (!strongDelegate) {
        return;
    }
    NSString *msg = NSStringFromStdString(entry.msg);
    PJBridgeLogLevel level = LogLevelFromPJSIP(entry.level);
    [strongDelegate bridgeDidReceiveLogMessage:msg level:level];
}

#pragma mark - PJCall

PJCall::PJCall(PJAccount &account,
               int callId,
               std::string accountIdURI,
               __weak id<PJBridgeDelegate> delegate)
    : pj::Call(account, callId),
      account_(account),
      accountIdURI_(std::move(accountIdURI)),
      delegate_(delegate) {}

PJCall::~PJCall() {
    stopVideoPreview();
}

void PJCall::stopVideoPreview() {
    if (videoPreview_) {
        try {
            videoPreview_->stop();
        } catch (const pj::Error &) {
        }
        videoPreview_.reset();
    }
}

PJBridgeCallInfo *PJCall::snapshotCallInfo() {
    PJBridgeCallInfo *info = [[PJBridgeCallInfo alloc] init];
    info.accountIdURI = NSStringFromStdString(accountIdURI_);
    info.isLocalHold = localHold_;
    info.isLocalMuted = localMuted_;
    info.isVideoMuted = videoMuted_;
    info.isVideo = hasVideo_;
    try {
        pj::CallInfo ci = getInfo();
        info.callId = ci.id;
        info.sipCallId = NSStringFromStdString(ci.callIdString);
        info.remoteURI = NSStringFromStdString(ci.remoteUri);
        info.remoteContact = NSStringFromStdString(ci.remoteContact);
        info.state = CallStateFromPJSIP(ci.state);
        info.stateText = NSStringFromStdString(ci.stateText);
        info.lastStatusCode = (int32_t)ci.lastStatusCode;
        info.lastReason = NSStringFromStdString(ci.lastReason);
        info.connectDuration = (NSTimeInterval)ci.connectDuration.sec + (NSTimeInterval)ci.connectDuration.msec / 1000.0;
        info.totalDuration = (NSTimeInterval)ci.totalDuration.sec + (NSTimeInterval)ci.totalDuration.msec / 1000.0;
    } catch (const pj::Error &) {
        info.callId = getId();
    }
    return info;
}

void PJCall::onCallState(pj::OnCallStateParam &prm) {
    (void)prm;
    pj::CallInfo ci;
    try {
        ci = getInfo();
    } catch (const pj::Error &) {
        return;
    }

    PJBridgeCallInfo *info = snapshotCallInfo();
    NSString *accURI = NSStringFromStdString(accountIdURI_);

    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (strongDelegate) {
        [strongDelegate bridgeAccount:accURI didChangeCallState:info];
    }

    if (ci.state == PJSIP_INV_STATE_DISCONNECTED) {
        stopVideoPreview();
        emitCallStats(ci);
        // Never destroy pj::Call synchronously inside its own onCallState callback.
        account_.removeCallDeferred(ci.id);
    }
}

void PJCall::onCallMediaState(pj::OnCallMediaStateParam &prm) {
    (void)prm;
    pj::CallInfo ci;
    try {
        ci = getInfo();
    } catch (const pj::Error &) {
        return;
    }

    bool anyVideoActive = false;
    bool localHoldDetected = false;
    UIView *localPreviewView = nil;
    UIView *remoteVideoView = nil;

    for (unsigned i = 0; i < ci.media.size(); ++i) {
        const pj::CallMediaInfo &mi = ci.media[i];
        if (mi.type == PJMEDIA_TYPE_AUDIO) {
            if (mi.status == PJSUA_CALL_MEDIA_ACTIVE || mi.status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
                try {
                    pj::AudioMedia audMed = getAudioMedia((int)i);
                    pj::AudDevManager &mgr = pj::Endpoint::instance().audDevManager();
                    if (!silentCall_) {
                        audMed.startTransmit(mgr.getPlaybackDevMedia());
                    }
                    if (!localMuted_) {
                        mgr.getCaptureDevMedia().startTransmit(audMed);
                    }
                    pj::StreamInfo si = getStreamInfo(i);
                    lastAudioCodec_ = si.codecName;
                } catch (const pj::Error &) {
                }
            } else if (mi.status == PJSUA_CALL_MEDIA_LOCAL_HOLD) {
                localHoldDetected = true;
            }
        } else if (mi.type == PJMEDIA_TYPE_VIDEO) {
            if (mi.status == PJSUA_CALL_MEDIA_ACTIVE) {
                anyVideoActive = true;
                // Extract native iOS UIView for remote video window
                if (mi.videoIncomingWindowId != PJSUA_INVALID_ID) {
                    try {
                        pj::VideoWindow vidWin(mi.videoIncomingWindowId);
                        pj::VideoWindowInfo winInfo = vidWin.getInfo();
                        if (winInfo.winHandle.type == PJMEDIA_VID_DEV_HWND_TYPE_IOS &&
                            winInfo.winHandle.handle.window != nullptr) {
                            remoteVideoView = (__bridge UIView *)winInfo.winHandle.handle.window;
                        }
                    } catch (const pj::Error &) {
                    }
                }
                // Extract native iOS UIView for local camera preview
                if (mi.videoCapDev != PJMEDIA_VID_INVALID_DEV) {
                    try {
                        currentCameraDevId_ = mi.videoCapDev;
                        if (!videoPreview_) {
                            videoPreview_ = std::make_unique<pj::VideoPreview>(mi.videoCapDev);
                            pj::VideoPreviewOpParam prevParam;
                            videoPreview_->start(prevParam);
                        }
                        pj::VideoWindow prevWin = videoPreview_->getVideoWindow();
                        pj::VideoWindowInfo prevInfo = prevWin.getInfo();
                        if (prevInfo.winHandle.type == PJMEDIA_VID_DEV_HWND_TYPE_IOS &&
                            prevInfo.winHandle.handle.window != nullptr) {
                            localPreviewView = (__bridge UIView *)prevInfo.winHandle.handle.window;
                        }
                    } catch (const pj::Error &) {
                    }
                }
            }
        }
    }

    hasVideo_ = anyVideoActive;
    if (localHoldDetected) {
        localHold_ = true;
    }

    NSString *accURI = NSStringFromStdString(accountIdURI_);
    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (strongDelegate) {
        [strongDelegate bridgeAccount:accURI
                didChangeMediaForCall:ci.id
                          isLocalHold:localHold_
                         isLocalMuted:localMuted_
                         isVideoMuted:videoMuted_
                              isVideo:hasVideo_];

        if (localPreviewView != nil || remoteVideoView != nil) {
            [strongDelegate bridgeAccount:accURI
                   didPrepareVideoForCall:ci.id
                             localPreview:localPreviewView
                              remoteVideo:remoteVideoView];
        }
    }
}

void PJCall::onCallTransferStatus(pj::OnCallTransferStatusParam &prm) {
    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (!strongDelegate) {
        return;
    }
    [strongDelegate bridgeAccount:NSStringFromStdString(accountIdURI_)
          didChangeTransferStatus:(int32_t)prm.statusCode
                           reason:NSStringFromStdString(prm.reason)
                          isFinal:(BOOL)prm.finalNotify
                          forCall:getId()];
}

void PJCall::onDtmfDigit(pj::OnDtmfDigitParam &prm) {
    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (!strongDelegate) {
        return;
    }
    [strongDelegate bridgeAccount:NSStringFromStdString(accountIdURI_)
              didReceiveDtmfDigit:NSStringFromStdString(prm.digit)
                          forCall:getId()];
}

void PJCall::onStreamDestroyed(pj::OnStreamDestroyedParam &prm) {
    (void)prm;
}

void PJCall::setLocalMute(bool muted) {
    localMuted_ = muted;
    applyAudioMuteState();

    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (strongDelegate) {
        [strongDelegate bridgeAccount:NSStringFromStdString(accountIdURI_)
                didChangeMediaForCall:getId()
                          isLocalHold:localHold_
                         isLocalMuted:localMuted_
                         isVideoMuted:videoMuted_
                              isVideo:hasVideo_];
    }
}

void PJCall::applyAudioMuteState() {
    pj::CallInfo ci = getInfo();
    pj::AudDevManager &mgr = pj::Endpoint::instance().audDevManager();
    for (unsigned i = 0; i < ci.media.size(); ++i) {
        const pj::CallMediaInfo &mi = ci.media[i];
        if (mi.type == PJMEDIA_TYPE_AUDIO &&
            (mi.status == PJSUA_CALL_MEDIA_ACTIVE || mi.status == PJSUA_CALL_MEDIA_REMOTE_HOLD)) {
            pj::AudioMedia audMed = getAudioMedia((int)i);
            if (localMuted_) {
                mgr.getCaptureDevMedia().stopTransmit(audMed);
            } else {
                mgr.getCaptureDevMedia().startTransmit(audMed);
            }
        }
    }
}

void PJCall::setLocalHold(bool hold) {
    if (localHold_ == hold) {
        return;
    }
    pj::CallOpParam prm(true);
    if (hold) {
        setHold(prm);
        localHold_ = true;
    } else {
        prm.opt.flag |= PJSUA_CALL_UNHOLD;
        reinvite(prm);
        localHold_ = false;
    }

    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (strongDelegate) {
        [strongDelegate bridgeAccount:NSStringFromStdString(accountIdURI_)
                didChangeMediaForCall:getId()
                          isLocalHold:localHold_
                         isLocalMuted:localMuted_
                         isVideoMuted:videoMuted_
                              isVideo:hasVideo_];
    }
}

void PJCall::setVideoMute(bool muted) {
    pj::CallVidSetStreamParam prm;
    prm.medIdx = -1;
    vidSetStream(muted ? PJSUA_CALL_VID_STRM_STOP_TRANSMIT : PJSUA_CALL_VID_STRM_START_TRANSMIT, prm);
    videoMuted_ = muted;

    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (strongDelegate) {
        [strongDelegate bridgeAccount:NSStringFromStdString(accountIdURI_)
                didChangeMediaForCall:getId()
                          isLocalHold:localHold_
                         isLocalMuted:localMuted_
                         isVideoMuted:videoMuted_
                              isVideo:hasVideo_];
    }
}

void PJCall::setSilentCall(bool silent) {
    silentCall_ = silent;
}

void PJCall::switchCamera() {
    pj::VidDevManager &vidMgr = pj::Endpoint::instance().vidDevManager();
    pj::VideoDevInfoVector2 devs = vidMgr.enumDev2();
    int nextCaptureDev = currentCameraDevId_;
    for (const auto &dev : devs) {
        if ((dev.dir & PJMEDIA_DIR_CAPTURE) != 0 && dev.id != currentCameraDevId_) {
            nextCaptureDev = dev.id;
            break;
        }
    }
    if (nextCaptureDev != currentCameraDevId_) {
        pj::CallVidSetStreamParam prm;
        prm.capDev = nextCaptureDev;
        vidSetStream(PJSUA_CALL_VID_STRM_CHANGE_CAP_DEV, prm);
        currentCameraDevId_ = nextCaptureDev;
    }
}

void PJCall::emitCallStats(const pj::CallInfo &ci) {
    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (!strongDelegate) {
        return;
    }

    PJBridgeCallStats *stats = [[PJBridgeCallStats alloc] init];
    stats.callId = ci.id;
    stats.accountIdURI = NSStringFromStdString(accountIdURI_);
    stats.duration = (NSTimeInterval)ci.connectDuration.sec + (NSTimeInterval)ci.connectDuration.msec / 1000.0;
    stats.callStatusCode = (int32_t)ci.lastStatusCode;
    stats.audioCodec = NSStringFromStdString(lastAudioCodec_);

    for (unsigned i = 0; i < ci.media.size(); ++i) {
        if (ci.media[i].type == PJMEDIA_TYPE_AUDIO) {
            try {
                pj::StreamStat st = getStreamStat(i);
                stats.rxPackets = st.rtcp.rxStat.pkt;
                stats.txPackets = st.rtcp.txStat.pkt;
                stats.rxPacketLoss = st.rtcp.rxStat.loss;
                stats.txPacketLoss = st.rtcp.txStat.loss;
                stats.rttMeanMs = (double)st.rtcp.rttUsec.mean / 1000.0;
                stats.rxJitterMeanMs = (double)st.rtcp.rxStat.jitterUsec.mean / 1000.0;
                stats.txJitterMeanMs = (double)st.rtcp.txStat.jitterUsec.mean / 1000.0;
                if (stats.audioCodec.length == 0) {
                    pj::StreamInfo si = getStreamInfo(i);
                    stats.audioCodec = NSStringFromStdString(si.codecName);
                }
            } catch (const pj::Error &) {
            }
            break;
        }
    }

    [strongDelegate bridgeAccount:NSStringFromStdString(accountIdURI_) didReceiveCallStats:stats];
}

#pragma mark - PJAccount

PJAccount::PJAccount(std::string accountIdURI, __weak id<PJBridgeDelegate> delegate)
    : accountIdURI_(std::move(accountIdURI)), delegate_(delegate) {}

PJAccount::~PJAccount() {
    std::lock_guard<std::mutex> lock(callsMutex_);
    calls_.clear();
}

void PJAccount::onRegState(pj::OnRegStateParam &prm) {
    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (!strongDelegate) {
        return;
    }
    BOOL isActive = NO;
    try {
        pj::AccountInfo ai = getInfo();
        isActive = ai.regIsActive ? YES : NO;
    } catch (const pj::Error &) {
        isActive = (prm.code >= 200 && prm.code < 300);
    }

    [strongDelegate bridgeAccount:NSStringFromStdString(accountIdURI_)
              didChangeRegStatus:(int32_t)prm.code
                          reason:NSStringFromStdString(prm.reason)
                        isActive:isActive];
}

void PJAccount::onIncomingCall(pj::OnIncomingCallParam &prm) {
    auto call = std::make_shared<PJCall>(*this, prm.callId, accountIdURI_, delegate_);
    registerCall(prm.callId, call);

    try {
        pj::CallOpParam ringParam;
        ringParam.statusCode = PJSIP_SC_RINGING;
        call->answer(ringParam);
    } catch (const pj::Error &) {
    }

    PJBridgeCallInfo *info = call->snapshotCallInfo();
    id<PJBridgeDelegate> strongDelegate = delegate_;
    if (strongDelegate) {
        [strongDelegate bridgeAccount:NSStringFromStdString(accountIdURI_) didReceiveCallInfo:info];
    }
}

std::shared_ptr<PJCall> PJAccount::createOutgoingCall() {
    return std::make_shared<PJCall>(*this, PJSUA_INVALID_ID, accountIdURI_, delegate_);
}

std::shared_ptr<PJCall> PJAccount::findCall(int callId) {
    std::lock_guard<std::mutex> lock(callsMutex_);
    auto it = calls_.find(callId);
    return it != calls_.end() ? it->second : nullptr;
}

void PJAccount::registerCall(int callId, std::shared_ptr<PJCall> call) {
    std::lock_guard<std::mutex> lock(callsMutex_);
    calls_[callId] = std::move(call);
}

void PJAccount::removeCallDeferred(int callId) {
    std::shared_ptr<PJCall> extracted;
    {
        std::lock_guard<std::mutex> lock(callsMutex_);
        auto it = calls_.find(callId);
        if (it != calls_.end()) {
            extracted = std::move(it->second);
            calls_.erase(it);
        }
    }
    if (extracted) {
        __block std::shared_ptr<PJCall> retained = std::move(extracted);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            retained.reset();
        });
    }
}

void PJAccount::holdAllCalls() {
    std::vector<std::shared_ptr<PJCall>> snapshot;
    {
        std::lock_guard<std::mutex> lock(callsMutex_);
        snapshot.reserve(calls_.size());
        for (const auto &kv : calls_) {
            snapshot.push_back(kv.second);
        }
    }
    for (auto &call : snapshot) {
        try {
            if (call->isActive() && !call->isLocalHold()) {
                call->setLocalHold(true);
            }
        } catch (const pj::Error &) {
        }
    }
}

void PJAccount::hangupAllCalls() {
    std::vector<std::shared_ptr<PJCall>> snapshot;
    {
        std::lock_guard<std::mutex> lock(callsMutex_);
        snapshot.reserve(calls_.size());
        for (const auto &kv : calls_) {
            snapshot.push_back(kv.second);
        }
    }
    for (auto &call : snapshot) {
        try {
            if (call->isActive()) {
                pj::CallOpParam prm;
                prm.statusCode = PJSIP_SC_DECLINE;
                call->hangup(prm);
            }
        } catch (const pj::Error &) {
        }
    }
}

} // namespace pjsipios
