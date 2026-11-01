# 星云 · Codex 1.2

李星云主题的 macOS Codex 窗口内开场与动态壁纸伴侣。

启动时，线稿与人物直接出现在 **Codex 自己的窗口内**；动画在原片尾部淡出前衔接到背景，侧栏、聊天区与输入框逐渐露出。人物位置保持一致，风动背景继续播放。Esc 或右下角按钮可以立即跳过。

五套素材可预览，启动动画与背景可独立选择，动态背景支持暂停、画面强度与恢复默认。为了获得连续衔接的效果，建议启动与背景选择同一套素材。

这是一个本机运行的原生菜单栏主题伴侣。最低 macOS 13；验证环境为 Intel Mac、macOS 15.7.9、Codex 26.1027.30824。没有云服务或 API Key 配置；无需另装工具类插件。

## 官方入口自动播放（1.2 本机补丁）

用户已明确授权修改官方应用并重新签名。此版本在官方应用主进程中注册启动处理，直接操作自己的 webContents，不开放调试端口，也没有登录启动项或常驻监听服务。

完全退出当前 Codex 后，照常从原来的官方图标启动。开场自动播放一次，随后保留动态背景。已运行的旧进程不会因磁盘安装而自动变成新版；正在进行的聊天无需被强制结束。

主题设置仍在「星云 · Codex」中：五套素材、独立启动/背景选择、暂停、强度及恢复默认。设置通过本机状态文件生效。「恢复默认」移除动画与背景；若要恢复 OpenAI 原始签名，请使用原版恢复工具。

### 安装流程和恢复

先在完整副本测试，禁止直接对运行中的应用文件原地覆写。`scripts/patch-official.py` 在 ASAR 末尾追加启动入口，保留原始数据，更新入口分块校验、ASAR 头摘要、Info.plist 和 Framework 内嵌摘要。完整性校验开关保持开启；不关闭 Gatekeeper、SIP 或任何系统保护。

```sh
# 对复制的官方应用运行；不用于当前安装包原地打补丁
python3 scripts/patch-official.py /absolute/path/to/copied/ChatGPT.app
# 验证副本后再部署；保存并校验原始官方签名备份
python3 scripts/install-official.py --candidate /absolute/path/to/copied/ChatGPT.app
# 先 Cmd+Q 完全退出 Codex，再恢复原版
python3 scripts/install-official.py --restore
```

部署使用目录原子交换，不覆写当前进程映射的二进制；完整官方原版保存在 `~/Library/Application Support/LiXingyunCodex/Backups/`，坐标记录在 `official-install.json`。安装与恢复均检查版本、SHA256 和严格代码签名校验，拒绝覆盖不匹配版本。

本地重签名不能继承 OpenAI 的开发者身份。官方钥匙串组、通知、应用组等能力和登录状态可能受影响，系统也可能重新请求权限。自动更新可能移除此补丁；更新后需重新验证，不自动重打补丁。仓库只保存自有主题源码、补丁工具和用户素材，不保存官方应用二进制或个人配置。

### 兼容旧版接入

未安装官方补丁时，伴侣保留 1.1 的手动启动方式，通过仅限本机 `127.0.0.1:9222` 的连接注入。该模式仍需从伴侣启动，并使用独立 `CodexProfile`。已打补丁的官方启动不需要这些参数，也不使用该独立配置目录。

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

`tests/browser-harness.mjs` 提供只访问本地测试素材的浏览器测试页，验证真实 H.264 播放、衔接、跳过、重复请求、尺寸变化及资源清理。它不会连接用户的 Codex。`tests/native-integration.mjs` 检查隔离副本的真实冷启动、暂停、恢复、重新启用和预览请求，测试状态目录与用户目录隔离。`tests/integration.mjs` 只用于旧版 CDP 测试实例。

本地构建进行 ad-hoc 签名。其他电脑需要在本机构建或使用 Apple 签名、公证后的发行包。

## 目录与卸载

- `Sources/`：原生 SwiftUI 素材库、AppKit 菜单栏与启动入口。
- `runtime/native-startup.cjs`：官方进程中的自有窗口接入、自动开场和本机设置同步。
- `runtime/bridge.mjs`：校验本机 Codex 进程身份、串行传输媒体、保存状态与重连。
- `runtime/intro-renderer.mjs`：同窗口开场、帧衔接、焦点与跳过处理。
- `runtime/wallpaper-layer.mjs`：统一静态背景的视口对齐。
- `runtime/vendor/`：基于 CCDawn/Codex-Dynamic-Skin v1.7.3 的 MIT 渲染器和样式；来源见 `ThirdParty/`。
- `~/Library/Application Support/LiXingyunCodex/`：本机状态与界面配置。

卸载 1.2 官方补丁时，先 Cmd+Q 完全退出 Codex，再运行 `python3 scripts/install-official.py --restore` 恢复完整官方签名原版。随后可退出并删除主题伴侣。仅选择「恢复默认」只关闭视觉效果，不会恢复官方签名。1.1 兼容模式退出后正常打开官方应用即可结束本地调试连接。

软件采用 MIT 许可，第三方许可证保存在 `ThirdParty/`。角色、商标及用户提供的媒体不属于软件许可证的授权范围。本项目与 OpenAI、《画江湖之不良人》官方无关。
