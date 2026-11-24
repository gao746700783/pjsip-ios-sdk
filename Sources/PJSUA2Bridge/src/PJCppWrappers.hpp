#pragma once

#include <pjsua2.hpp>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#import "PJBridgeTypes.h"
#import "PJBridgeDelegate.h"

namespace pjsipios {

class PJAccount;
class PJCall;

NSError *NSErrorFromPJError(const pj::Error &err);
NSString *NSStringFromStdString(const std::string &str);
std::string StdStringFromNSString(NSString * _Nullable str);
PJBridgeCallState CallStateFromPJSIP(pjsip_inv_state state);
PJBridgeLogLevel LogLevelFromPJSIP(int level);
pjmedia_orient MediaOrientFromBridge(PJBridgeVideoOrientation orient);

class PJLogWriter final : public pj::LogWriter {
public:
    explicit PJLogWriter(__weak id<PJBridgeDelegate> delegate);
    void write(const pj::LogEntry &entry) override;

private:
    __weak id<PJBridgeDelegate> delegate_;
};

class PJCall final : public pj::Call {
public:
    PJCall(PJAccount &account,
           int callId,
           std::string accountIdURI,
           __weak id<PJBridgeDelegate> delegate);
    ~PJCall() override;

    void onCallState(pj::OnCallStateParam &prm) override;
    void onCallMediaState(pj::OnCallMediaStateParam &prm) override;
    void onCallTransferStatus(pj::OnCallTransferStatusParam &prm) override;
    void onDtmfDigit(pj::OnDtmfDigitParam &prm) override;
    void onStreamDestroyed(pj::OnStreamDestroyedParam &prm) override;

    void setLocalMute(bool muted);
    void setLocalHold(bool hold);
    void setVideoMute(bool muted);
    void setSilentCall(bool silent);
    void switchCamera();
    void stopVideoPreview();

    bool isLocalMuted() const { return localMuted_; }
    bool isLocalHold() const { return localHold_; }
    bool isVideoMuted() const { return videoMuted_; }
    bool isVideoCall() const { return hasVideo_; }

    PJBridgeCallInfo *snapshotCallInfo();

private:
    void applyAudioMuteState();
    void emitCallStats(const pj::CallInfo &ci);

    PJAccount &account_;
    std::string accountIdURI_;
    __weak id<PJBridgeDelegate> delegate_;
    bool localMuted_ = false;
    bool localHold_ = false;
    bool videoMuted_ = false;
    bool silentCall_ = false;
    bool hasVideo_ = false;
    int currentCameraDevId_ = PJMEDIA_VID_DEFAULT_CAPTURE_DEV;
    std::string lastAudioCodec_;
    std::unique_ptr<pj::VideoPreview> videoPreview_;
};

class PJAccount final : public pj::Account {
public:
    PJAccount(std::string accountIdURI, __weak id<PJBridgeDelegate> delegate);
    ~PJAccount() override;

    void onRegState(pj::OnRegStateParam &prm) override;
    void onIncomingCall(pj::OnIncomingCallParam &prm) override;

    std::shared_ptr<PJCall> createOutgoingCall();
    std::shared_ptr<PJCall> findCall(int callId);
    void registerCall(int callId, std::shared_ptr<PJCall> call);
    void removeCallDeferred(int callId);
    void holdAllCalls();
    void hangupAllCalls();

    const std::string &accountIdURI() const { return accountIdURI_; }

private:
    std::string accountIdURI_;
    __weak id<PJBridgeDelegate> delegate_;
    mutable std::mutex callsMutex_;
    std::unordered_map<int, std::shared_ptr<PJCall>> calls_;
};

} // namespace pjsipios
