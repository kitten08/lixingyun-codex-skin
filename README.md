# 星云 · Codex

李星云主题的 macOS Codex 启动动画与背景壁纸伴侣。五套素材可预览，启动动画与背景可独立选择，动态背景支持暂停、画面强度与恢复默认。

这是一个本机运行的原生菜单栏应用。最低 macOS 13；本次构建、媒体解码与实际注入验证环境为 Intel Mac、macOS 15.7.9、Codex 26.1027.30824。没有云服务、账号登录或 API Key 配置。

## 使用

打开 `星云 · Codex.app`，在五张卡片中选择背景，点击「应用此壁纸」。右侧可独立选择启动动画，点击「预览启动动画」查看，Esc 跳过。

若 Codex 已在运行且未开放本地调试连接，设置会先保存。请结束当前任务，完全退出 Codex，再从本应用的「启动 Codex」进入。启动动画播放一次，随后打开官方 Codex 并连接背景。关闭设置窗口后，本应用留在菜单栏「星云」。以后从伴侣应用启动可播放动画；直接打开官方 Codex 不会经过独立启动播放器。

背景通过仅限本机 `127.0.0.1:9222` 的 Chromium 调试连接注入。官方应用包及签名保持完整。此连接只在通过伴侣启动的 Codex 进程存活期间开放，同机其他进程也可能连接。完全退出 Codex，再直接打开官方应用即可结束此连接。恢复默认会清理渲染器背景并关闭自动重应用。Codex 更新后可能需要重新验证兼容性。

## 五套素材

| 预设 | 启动 | 背景 |
| --- | --- | --- |
| 墨影 · 线稿显现 | 原始 v2 MP4 | 完整显现后的静帧 |
| 风起 · 你欲何为 | 原始 v3 风动 MP4 | 8 秒无字无缝风动循环 |
| 静夜 · 你欲何为 | 原始 v4 无风动 MP4 | 「你欲何为」静帧 |
| 宣纸 · 风动 | 原白底 GIF 按原时序转 MP4 | 白底动态循环 |
| 留白 · 定格 | 原白底定格 GIF 转 MP4 | 白底定格画面 |

原始五个文件完整保存在 `Assets/originals/`。仓库含私人角色素材，请保持仓库私有。

## 构建和验证

需要 Apple Command Line Tools，以及已安装的官方 Codex。无 npm / pip 依赖。

```sh
./scripts/build.sh
"build/星云 · Codex.app/Contents/MacOS/LiXingyunSkin" --verify
node --test tests/bridge.test.mjs
node runtime/bridge.mjs validate --assets Assets
```

`scripts/media.swift` 用 AVFoundation 将 GIF 转为 H.264，并从原视频抽取海报。预处理后的资源已保存，普通构建无需重新转码。

```sh
swiftc -O scripts/media.swift -o /tmp/lixingyun-media
/tmp/lixingyun-media Assets
```

本地构建会进行 ad-hoc 签名。若移到其他电脑，需要在该电脑构建或使用 Apple 签名、公证后的发行包。

## 目录与卸载

- `Sources/`：原生 SwiftUI 素材库、AppKit 菜单栏与启动播放器。
- `runtime/bridge.mjs`：校验本机 Codex 进程身份、分块传输媒体、保存状态与重连。
- `runtime/vendor/`：基于 CCDawn/Codex-Dynamic-Skin v1.7.3 的 MIT 渲染器和样式；来源见 `ThirdParty/`。
- `~/Library/Application Support/LiXingyunCodex/`：本机背景状态。
- `local.codex.lixingyun.skin`：本机启动动画偏好。

卸载前选择「恢复 Codex 默认外观」，退出本应用，把 `星云 · Codex.app` 移到废纸篓。偏好与状态可保留，以便以后恢复；卸载后完全退出并正常打开官方 Codex 即可。

软件采用 MIT 许可，第三方许可证保存在 `ThirdParty/`。角色、商标及用户提供的媒体不属于软件许可证的授权范围。本项目与 OpenAI、《画江湖之不良人》官方无关。
