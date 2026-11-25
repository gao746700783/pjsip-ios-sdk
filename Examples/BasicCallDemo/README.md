# 最小音频呼叫 Demo

用于验证本地 SDK 的「启动 → TCP 注册 → 音频呼出 → 挂断」流程。使用 SwiftUI，最低 iOS 15，只在前台运行；不接入 CallKit、视频或后台呼叫。

## 运行

- 用 Xcode 打开 [BasicCallDemo.xcodeproj](./BasicCallDemo.xcodeproj)。工程通过相对路径引用仓库根目录的本地 `PJSIPiOS` Package，无需发布 SDK。
- 在 app target 的 Signing & Capabilities 中选择自己的 Team，必要时修改 Bundle Identifier。选择 iPhone 真机运行，首次允许麦克风与本地网络权限。
- 准备一个支持 TCP 的 SIP/PBX 服务器、一个可注册账号和一个可接听的分机或软电话；两端需要能连通 SIP 与 RTP 端口。这里不会自动创建服务器或账号。
- 输入 Server host or IP（不带 `sip:`）、Port（默认 `5060`）、Username 和 Password，点击 **Register**。账号和密码不写入 Keychain，密码在账号提交成功后从输入框清空。
- 等待显示 `Registration: 200 ... active=true`。输入完整目标 URI，例如 `sip:1002@192.168.1.10:5060`，点击 **Call**，让另一端接听。
- 确认状态进入 `CONFIRMED`，双方能互相听到声音；点击 **Hang up**，确认 `DISCONNECTED`，再拨一次确认可重复呼叫。
- 点击 **Disconnect** 停止 SIP 栈并释放音频会话，然后可修改账号重新注册。注册失败也可以用这个按钮重置。

默认通过听筒播放，请贴近听筒或使用耳机。Demo 仅支持 TCP、普通 RTP 的主动呼出；请使用与此配置一致的测试服务器，并保持 app 在前台。

## 排查

- 注册 `401` 可能是正常鉴权挑战，应等待最终 `200`；持续 `403` 检查账号密码，超时检查服务器地址、端口、防火墙及网络。
- 呼叫 `404` 检查目标分机与 URI；`486` 通常表示对方忙。
- 已接通但单向或无声：检查两端麦克风权限、音频路由和 RTP/NAT 网络，优先在同一局域网测试。
- 编译成功只说明工程和接口可用；真实注册及双向语音仍须用自己的服务器和设备按上述步骤验证。
