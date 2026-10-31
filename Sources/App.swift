import AppKit
import SwiftUI
import AVKit

struct Preset: Codable, Identifiable {
    let id, name, subtitle, startup, wallpaper, wallpaperType, poster: String
}
let resources = Bundle.main.resourceURL!
let assets = resources.appendingPathComponent("Assets")
let presets = (try? JSONDecoder().decode([Preset].self, from: Data(contentsOf: assets.appendingPathComponent("presets.json")))) ?? []
let defaults = UserDefaults.standard
let targetURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
let nodeURL = targetURL.appendingPathComponent("Contents/Resources/cua_node/bin/node")

final class Model: ObservableObject {
    @Published var selected = defaults.string(forKey: "wallpaper") ?? "wind"
    @Published var startup = defaults.string(forKey: "startup") ?? "wind"
    @Published var opacity = defaults.object(forKey: "opacity") as? Double ?? 0.70
    @Published var paused = false
    @Published var busy = false
    @Published var status = "选择一套李星云主题，开启你的江湖。"
    @Published var connected = false
    @Published var enabled = false
    var watcher: Process?
    let queue = DispatchQueue(label: "local.codex.lixingyun.bridge")
    var current: Preset { presets.first(where: {$0.id == selected}) ?? presets[0] }
    func save() { defaults.set(selected, forKey: "wallpaper"); defaults.set(startup, forKey: "startup"); defaults.set(opacity, forKey: "opacity") }
    func command(_ arguments: [String], completion: (([String:Any]) -> Void)? = nil) {
        busy = true
        queue.async {
            let result = self.run(arguments)
            DispatchQueue.main.async {
                self.busy = false
                self.status = result["message"] as? String ?? "操作完成"
                if let c = result["connected"] as? Bool {self.connected = c}
                if let e = result["enabled"] as? Bool {self.enabled = e}
                completion?(result)
            }
        }
    }
    func run(_ arguments: [String]) -> [String:Any] {
        let process = Process(); process.executableURL = nodeURL
        process.arguments = [resources.appendingPathComponent("runtime/bridge.mjs").path] + arguments + ["--assets", assets.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (try? JSONSerialization.jsonObject(with: data) as? [String:Any]) ?? ["ok":false,"message":"背景连接未返回有效结果"]
        } catch { return ["ok":false,"message":"无法启动背景连接：\(error.localizedDescription)"] }
    }
    func apply() {save();command(["apply","--preset",selected,"--opacity",String(opacity)])}
    func pause() {paused.toggle();command(["pause","--paused",String(paused)])}
    func restore() {paused = false; command(["restore"])}
    func setOpacity() {save();command(["opacity","--value",String(opacity)])}
    func refresh() {command(["status"]) { result in
        if let p = result["paused"] as? Bool {self.paused = p}
    }}
    func startWatch() {
        guard watcher == nil else {return}
        let p = Process(); p.executableURL = nodeURL
        p.arguments = [resources.appendingPathComponent("runtime/bridge.mjs").path,"watch","--assets",assets.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do {try p.run();watcher = p} catch {status = "背景连接尚未启动"}
    }
    func stopWatch() {if let p = watcher, p.isRunning {p.terminate()};watcher = nil}
}

struct VideoSurface: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.controlsStyle = .floating
        view.videoGravity = .resizeAspect; view.player = AVPlayer(url: url)
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if let item = view.player?.currentItem?.asset as? AVURLAsset, item.url == url {return}
        view.player?.pause(); view.player = AVPlayer(url:url)
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {view.player?.pause()}
}

struct Gallery: View {
    @ObservedObject var model: Model
    var intro: () -> Void
    var launch: () -> Void
    @State var moviePreview = false
    private let crimson = Color(red:0.75,green:0.24,blue:0.26)
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(alignment:.center) {
                VStack(alignment:.leading,spacing:5) {
                    Text("星云 · CODEX").font(.system(size:12,weight:.medium,design:.monospaced)).tracking(3).foregroundColor(.secondary)
                    Text("你欲何为").font(.system(size:34,weight:.semibold,design:.serif)).tracking(7)
                }
                Spacer()
                HStack(spacing:7) { Circle().fill(model.connected ? Color.green : Color.orange).frame(width:6,height:6); Text(model.connected ? "背景已连接" : "等待 Codex 连接").font(.system(size:12)) }.foregroundColor(.secondary)
                Button(action:launch) {Label("启动 Codex",systemImage:"play.fill").padding(.horizontal,10).padding(.vertical,5)}.buttonStyle(.borderedProminent).tint(crimson)
            }
            HStack(alignment:.top,spacing:22) {
                VStack(alignment:.leading,spacing:10) {
                    ZStack {
                        Color.black
                        if moviePreview {
                            VideoSurface(url:assets.appendingPathComponent(model.current.startup)).id(model.selected)
                        } else if let image = NSImage(contentsOf:assets.appendingPathComponent(model.current.poster)) {
                            Image(nsImage:image).resizable().aspectRatio(contentMode:.fit)
                        }
                    }.aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:14))
                    HStack {
                        Text(model.current.name).font(.system(size:15,weight:.semibold))
                        Spacer()
                        Toggle("视频预览",isOn:$moviePreview).toggleStyle(.switch).controlSize(.mini).font(.system(size:11))
                    }
                    Text(model.current.subtitle).font(.system(size:12)).foregroundColor(.secondary)
                }.frame(maxWidth:.infinity)
                VStack(alignment:.leading,spacing:17) {
                    Text("播放设置").font(.system(size:14,weight:.semibold))
                    VStack(alignment:.leading,spacing:7) {
                        Text("启动时播放一次").font(.system(size:11)).foregroundColor(.secondary)
                        Picker("",selection:$model.startup) {ForEach(presets) {p in Text(p.name).tag(p.id)}}.labelsHidden().onChange(of:model.startup) {_ in model.save()}
                        Button("预览启动动画",action:intro).frame(maxWidth:.infinity)
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:7) {
                        Text("Codex 内背景").font(.system(size:11)).foregroundColor(.secondary)
                        Text(model.current.name).font(.system(size:12,weight:.medium))
                        HStack { Text("画面强度");Spacer();Text("\(Int(model.opacity*100))%").monospacedDigit() }.font(.system(size:11)).foregroundColor(.secondary)
                        Slider(value:$model.opacity,in:0...1,onEditingChanged:{editing in if !editing {model.setOpacity()}}).tint(crimson)
                        Button("应用此壁纸") {model.apply()}.buttonStyle(.borderedProminent).tint(crimson).disabled(model.busy)
                        HStack {
                            Button(model.paused ? "继续动态" : "暂停动态") {model.pause()}
                            Button("恢复默认") {model.restore()}
                        }.controlSize(.small)
                    }
                    Spacer(minLength:0)
                    Text("关闭窗口后仍可从菜单栏打开。\n下次从本应用启动 Codex，即会播放所选动画。")
                        .font(.system(size:10)).foregroundColor(.secondary).lineSpacing(3)
                }.frame(width:238)
            }
            HStack {Text("五种意境").font(.system(size:13,weight:.semibold));Spacer();Text("点击选择背景 · 启动动画可单独设置").font(.system(size:11)).foregroundColor(.secondary)}
            HStack(spacing:12) {
                ForEach(presets) {p in
                    Button {model.selected = p.id;model.save();moviePreview = false} label: {
                        VStack(alignment:.leading,spacing:7) {
                            if let image = NSImage(contentsOf:assets.appendingPathComponent(p.poster)) {
                                Image(nsImage:image).resizable().aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:7))
                            }
                            HStack { Text(p.name).font(.system(size:11,weight:.medium));Spacer(minLength:0);if model.selected==p.id {Image(systemName:"checkmark.circle.fill").foregroundColor(crimson)} }
                            Text(p.wallpaperType=="video" ? "动态背景" : "静态背景").font(.system(size:10)).foregroundColor(.secondary)
                        }.padding(8).background(model.selected==p.id ? Color.white.opacity(0.09) : Color.white.opacity(0.025))
                        .clipShape(RoundedRectangle(cornerRadius:11))
                        .overlay(RoundedRectangle(cornerRadius:11).stroke(model.selected==p.id ? crimson.opacity(0.8) : Color.white.opacity(0.07),lineWidth:1))
                    }.buttonStyle(.plain)
                }
            }
            HStack(alignment:.top,spacing:10) {
                Image(systemName:model.connected ? "checkmark.circle" : "info.circle").foregroundColor(model.connected ? .green : .secondary)
                VStack(alignment:.leading,spacing:3) {
                    Text(model.status).font(.system(size:11)).textSelection(.enabled)
                    if !model.connected {Text("已有 Codex 正在运行时，请先结束任务并完全退出，再点击「启动 Codex」。").font(.system(size:10)).foregroundColor(.secondary)}
                }
                Spacer();Button("刷新") {model.refresh()}.controlSize(.mini)
            }.padding(12).background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:9))
        }.padding(26).frame(minWidth:1020,minHeight:730).background(Color(red:0.065,green:0.071,blue:0.084)).preferredColorScheme(.dark)
    }
}

final class SplashWindow: NSWindow {
    var skip:(()->Void)?
    override var canBecomeKey: Bool {true}
    override func keyDown(with event: NSEvent) {if event.keyCode==53 {skip?()} else {super.keyDown(with:event)}}
}
final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = Model()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var splash: SplashWindow?
    var player: AVPlayer?
    var observer: NSObjectProtocol?
    var failureObserver: NSObjectProtocol?
    var done: (() -> Void)?
    var splashTimer: Timer?
    var connectionTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard presets.count==5 else { let a=NSAlert();a.messageText="素材库不完整，请重新安装完整应用。";a.runModal();NSApp.terminate(nil);return }
        NSApp.setActivationPolicy(.regular)
        makeMenu()
        makeWindow()
        model.startWatch(); model.refresh()
        connectionTimer = Timer.scheduledTimer(withTimeInterval:8,repeats:true) { [weak self] _ in
            guard let self=self,self.window.isVisible,!self.model.busy else {return}
            self.model.refresh()
        }
        if CommandLine.arguments.contains("--preview") {previewIntro()}
        else if CommandLine.arguments.contains("--launch") || (defaults.bool(forKey:"hasOpened") && !CommandLine.arguments.contains("--settings")) {launch()}
        else {showSettings()}
        defaults.set(true,forKey:"hasOpened")
    }
    func makeMenu() {
        let main=NSMenu();let appMenu=NSMenu()
        appMenu.addItem(withTitle:"关于星云 · Codex",action:#selector(about),keyEquivalent:"")
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"主题设置…",action:#selector(showSettings),keyEquivalent:",")
        appMenu.addItem(withTitle:"退出星云 · Codex",action:#selector(quit),keyEquivalent:"q")
        let item=NSMenuItem();item.submenu=appMenu;main.addItem(item);NSApp.mainMenu=main
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.title="星云"
        let menu=NSMenu()
        for (title,action) in [("主题设置…",#selector(showSettings)),("播放动画并打开 Codex",#selector(launch)),("暂停 / 继续动态背景",#selector(pause)),("恢复 Codex 默认外观",#selector(restore))] {let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;menu.addItem(i)}
        menu.addItem(.separator());let q=NSMenuItem(title:"退出星云 · Codex",action:#selector(quit),keyEquivalent:"");q.target=self;menu.addItem(q);statusItem.menu=menu
        for item in appMenu.items {item.target=self}
    }
    func makeWindow() {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="星云 · Codex";window.titlebarAppearsTransparent=true;window.backgroundColor=NSColor(calibratedWhite:0.07,alpha:1)
        window.minSize=NSSize(width:1050,height:760);window.delegate=self;window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:Gallery(model:model,intro:{[weak self] in self?.previewIntro()},launch:{[weak self] in self?.launch()}));window.center()
    }
    @objc func showSettings() {window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);if !model.busy {model.refresh()}}
    @objc func previewIntro() {playIntro { [weak self] in self?.showSettings() }}
    @objc func launch() {model.save();window.orderOut(nil);playIntro { [weak self] in self?.openCodex() }}
    func playIntro(completion:@escaping()->Void) {
        guard splash==nil,let preset=presets.first(where:{$0.id==model.startup}) else {return}
        let url=assets.appendingPathComponent(preset.startup)
        let visible=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let width=min(1280,visible.width*0.90,visible.height*0.9*16/9), size=NSSize(width:width,height:width*9/16)
        let w=SplashWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false;w.backgroundColor = .black;w.hasShadow=true;w.level = .floating
        let content=NSView(frame:NSRect(origin:.zero,size:size));content.wantsLayer=true;content.layer?.cornerRadius=14;content.layer?.masksToBounds=true
        let p=AVPlayer(url:url),layer=AVPlayerLayer(player:p);layer.frame=content.bounds;layer.videoGravity = .resizeAspect;content.layer?.addSublayer(layer)
        let skip=NSButton(title:"跳过  Esc",target:self,action:#selector(finishIntro));skip.frame=NSRect(x:size.width-112,y:15,width:95,height:28);skip.bezelStyle = .inline;skip.contentTintColor = .gray;content.addSubview(skip)
        w.contentView=content;w.skip={[weak self] in self?.finishIntro()};w.center();w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        splash=w;player=p;done=completion
        observer=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:p.currentItem,queue:.main){[weak self] _ in self?.finishIntro()}
        failureObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemFailedToPlayToEndTime,object:p.currentItem,queue:.main){[weak self] _ in self?.finishIntro()}
        splashTimer=Timer.scheduledTimer(withTimeInterval:12,repeats:false){[weak self] _ in self?.finishIntro()};p.play()
    }
    @objc func finishIntro() {
        guard splash != nil else {return};player?.pause();splash?.orderOut(nil);splash=nil;player=nil;splashTimer?.invalidate();splashTimer=nil
        if let o=observer {NotificationCenter.default.removeObserver(o)};observer=nil
        if let o=failureObserver {NotificationCenter.default.removeObserver(o)};failureObserver=nil
        let callback=done;done=nil;callback?()
    }
    func openCodex() {
        let running=NSRunningApplication.runningApplications(withBundleIdentifier:"com.openai.codex").filter{!$0.isTerminated}
        if let app=running.first {
            app.activate(options:[.activateAllWindows,.activateIgnoringOtherApps]);model.apply();return
        }
        let config=NSWorkspace.OpenConfiguration();config.activates=true
        let profile=URL(fileURLWithPath:NSHomeDirectory()).appendingPathComponent("Library/Application Support/LiXingyunCodex/CodexProfile")
        do {try FileManager.default.createDirectory(at:profile,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
        catch {model.status="无法建立本地界面配置：\(error.localizedDescription)";showSettings();return}
        config.arguments=["--user-data-dir=\(profile.path)","--remote-debugging-address=127.0.0.1","--remote-debugging-port=9222"]
        NSWorkspace.shared.openApplication(at:targetURL,configuration:config){[weak self] _,error in
            DispatchQueue.main.async {guard let self=self else{return};if let e=error {self.model.status="无法打开 Codex：\(e.localizedDescription)";self.showSettings()} else {self.model.apply()}}
        }
    }
    @objc func pause() {model.pause()}
    @objc func restore() {model.restore();showSettings()}
    @objc func about() {let a=NSAlert();a.messageText="星云 · Codex 1.0";a.informativeText="李星云启动动画与动态壁纸\n五套私人素材 · 本机运行\n基于 Codex Dynamic Skin 的 MIT 渲染器。";a.runModal()}
    @objc func quit() {NSApp.terminate(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {showSettings();return true}
    func applicationWillTerminate(_ notification:Notification) {connectionTimer?.invalidate();model.stopWatch();player?.pause()}
}

if CommandLine.arguments.contains("--verify") {
    do {
        guard presets.count==5 else {throw NSError(domain:"Assets",code:1)}
        for preset in presets {
            for relative in [preset.startup,preset.wallpaper,preset.poster] {guard FileManager.default.fileExists(atPath:assets.appendingPathComponent(relative).path) else {throw NSError(domain:relative,code:2)}}
            let asset=AVURLAsset(url:assets.appendingPathComponent(preset.startup))
            let generator=AVAssetImageGenerator(asset:asset)
            let frame=try generator.copyCGImage(at:CMTime(seconds:2,preferredTimescale:600),actualTime:nil)
            print("\(preset.id): \(frame.width)×\(frame.height), \(CMTimeGetSeconds(asset.duration)) seconds")
        }
        print("All five presets verified");exit(0)
    } catch {fputs("Media verification failed: \(error)\n",stderr);exit(1)}
}
let app=NSApplication.shared,delegate=Delegate();app.delegate=delegate;app.run()
