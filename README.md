# 星云 · Codex 1.1

李星云主题的 macOS Codex 窗口内开场与动态壁纸伴侣。

启动时，线稿与人物直接出现在 **Codex 自己的窗口内**；动画在原片尾部淡出前衔接到背景，侧栏、聊天区与输入框逐渐露出。人物位置保持一致，风动背景继续播放。Esc 或右下角按钮可以立即跳过。

五套素材可预览，启动动画与背景可独立选择，动态背景支持暂停、画面强度与恢复默认。为了获得连续衔接的效果，建议启动与背景选择同一套素材。

这是一个本机运行的原生菜单栏主题伴侣。最低 macOS 13；验证环境为 Intel Mac、macOS 15.7.9、Codex 26.1027.30824。没有云服务或 API Key 配置；无需另装工具类插件。

## 使用

打开 `星云 · Codex.app`，选择背景，在右侧选择对应的启动动画。点击「在 Codex 中预览」或「启动 Codex」，即可观看同窗口开场。开场结束后留在正常的 Codex 界面中。

当前 Codex 已开放本地连接时可以直接播放。如果 Codex 以普通方式启动且连接未开放，设置会先保存；请结束当前任务，完全退出 Codex，再从本应用启动。以后也从本应用进入，以播放开场。直接打开官方 Codex 不会自动经过这套开场。

关闭设置窗口后，本应用留在菜单栏「星云」。启动、背景、暂停与恢复默认均可在菜单栏或设置窗口中操作。「恢复默认」同时移除尚未结束的开场和常驻背景。

## 接入方式

背景和开场通过仅限本机 `127.0.0.1:9222` 的 Chromium 调试连接注入。开场是渲染器中的临时覆盖层，结束后会移除，并释放视频、Blob 与事件监听器。常驻图片和视频共用视口大小与对齐方式。

官方应用包及签名保持完整。这不是官方插件管理器中的工具插件。此连接只在通过伴侣启动的 Codex 进程存活期间开放，同机其他进程也可能连接。完全退出 Codex，再直接打开官方应用即可结束此连接。Codex 更新后可能需要重新验证兼容性。

为兼容当前 Codex 的本地连接启动方式，伴侣使用 `~/Library/Application Support/LiXingyunCodex/CodexProfile/` 保存独立的界面配置。首次可能需要重新选择界面偏好；启动的仍是已安装的官方 Codex，项目目录和 `~/.codex` 不会迁移。

## 五套素材

| 预设 | 启动素材 | 背景 |
| --- | --- | --- |
| 墨影 · 线稿显现 | 原始 v2 MP4 | 完整显现后的静帧 |
| 风起 · 你欲何为 | 原始 v3 风动 MP4 | 8 秒无字无缝风动循环 |
| 静夜 · 你欲何为 | 原始 v4 无风动 MP4 | 「你欲何为」静帧 |
| 宣纸 · 风动 | 原白底 GIF 按原时序转 MP4 | 独立白底风动循环，保留文字 |
| 留白 · 定格 | 原白底定格 GIF 转 MP4 | 白底定格画面 |

原始五个文件完整还原后位于 `Assets/originals/`，已安装应用含完整资源。大文件在仓库的 `AssetParts/` 中无损分块保存，构建脚本自动拼回并校验 SHA-256，无需 Git LFS 或额外下载。仓库含私人角色素材，请保持仓库私有。

## 构建和验证

需要 Apple Command Line Tools，以及已安装的官方 Codex。无 npm / pip 依赖。

```sh
./scripts/build.sh
"build/星云 · Codex.app/Contents/MacOS/LiXingyunSkin" --verify
node --test tests/bridge.test.mjs
node runtime/bridge.mjs validate --assets Assets
```

若只需还原并检查素材，可运行 `node scripts/restore-assets.mjs`。`scripts/media.swift` 保存 GIF 转码与海报抽帧逻辑；`scripts/render-white-loop.swift` 保存白底持续风动渲染源码。预处理资源已保存，普通构建无需重新转码。

`tests/browser-harness.mjs` 提供只访问本地测试素材的浏览器测试页，验证真实 H.264 播放、衔接、跳过、重复请求、尺寸变化及资源清理。它不会连接用户的 Codex。`tests/integration.mjs` 只用于单独启动的 Codex 测试实例。

本地构建进行 ad-hoc 签名。其他电脑需要在本机构建或使用 Apple 签名、公证后的发行包。

## 目录与卸载

- `Sources/`：原生 SwiftUI 素材库、AppKit 菜单栏与启动入口。
- `runtime/bridge.mjs`：校验本机 Codex 进程身份、串行传输媒体、保存状态与重连。
- `runtime/intro-renderer.mjs`：同窗口开场、帧衔接、焦点与跳过处理。
- `runtime/wallpaper-layer.mjs`：统一静态背景的视口对齐。
- `runtime/vendor/`：基于 CCDawn/Codex-Dynamic-Skin v1.7.3 的 MIT 渲染器和样式；来源见 `ThirdParty/`。
- `~/Library/Application Support/LiXingyunCodex/`：本机状态与界面配置。

卸载前选择「恢复 Codex 默认外观」，退出本应用，把 `星云 · Codex.app` 移到废纸篓。偏好与状态可保留；完全退出并正常打开官方 Codex 即可结束本地调试连接。

软件采用 MIT 许可，第三方许可证保存在 `ThirdParty/`。角色、商标及用户提供的媒体不属于软件许可证的授权范围。本项目与 OpenAI、《画江湖之不良人》官方无关。
