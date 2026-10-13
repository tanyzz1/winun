package winun.app

import std.collection.*
import winun.config.*
import winun.core.*
import winun.domain.*
import winun.infra.*
import winun.platform.*
import winun.win32.*

// 宿主层：装配平台实现、注册热键、跑消息循环、处理热重载
public class Host {
    public var cfg: ConfigSnapshot
    let log: Logger
    let backend: Win32WindowBackend
    let launcher: Win32Launcher
    let hotkeys: Win32Hotkeys
    let clock: Win32Clock
    public var dispatcher: Dispatcher
    var hotkeyActions: HashMap<Int32, Action> = HashMap<Int32, Action>()

    public init(cfg: ConfigSnapshot, log: Logger) {
        this.cfg = cfg
        this.log = log
        this.backend = Win32WindowBackend()
        this.launcher = Win32Launcher()
        this.hotkeys = Win32Hotkeys()
        this.clock = Win32Clock()
        this.dispatcher = Dispatcher(this.backend, this.launcher, this.hotkeys, this.clock, cfg, log)
    }

    public func registerHotkeys(): Int64 {
        this.hotkeyActions.clear()
        var id: Int32 = 1
        var ok: Int64 = 0
        for (binding in this.cfg.hotkeys) {
            if (this.hotkeys.register(binding.chord, id, binding.action)) {
                this.hotkeyActions.add(id, binding.action)
                ok = ok + 1
                this.log.info("host", "热键已注册：" + binding.chordText + " -> " + binding.actionText)
            } else {
                this.log.warn("host", "热键注册失败：" + binding.chordText +
                    "（该组合键已被其它程序占用；用 winun selftest --config 可探测空闲组合键）")
            }
            id = id + 1
        }
        return ok
    }

    public func warmUp(): Int64 {
        return this.dispatcher.registry.refresh(this.backend, this.cfg)
    }

    public func startGroup(): Unit {
        if (!this.cfg.startupGroup.isEmpty()) {
            this.dispatcher.dispatch(Action.GroupActivate(this.cfg.startupGroup))
        }
    }

    public func run(): Int64 {
        this.log.info("host", "winun 已启动，等待热键（线程 " + currentThreadId().toString() + "）")
        while (true) {
            let pumped = pumpMessage()
            if (pumped.result <= 0) {
                break
            }
            if (pumped.isHotkey()) {
                let id = pumped.hotkeyId()
                this.log.debug("host", "收到热键消息 id=" + id.toString())
                match (this.hotkeyActions.get(id)) {
                    case Some(action) => this.dispatcher.dispatch(action)
                    case None => this.log.debug("host", "未知热键 id=" + id.toString())
                }
            } else {
                translateMessage(pumped.msg)
                dispatchMessage(pumped.msg)
            }
            if (this.dispatcher.shouldQuit) {
                this.log.info("host", "收到退出动作，准备结束")
                postQuit()
                break
            }
            if (this.dispatcher.reloadRequested) {
                this.dispatcher.reloadRequested = false
                this.reload()
            }
        }
        this.hotkeys.unregisterAll()
        return 0
    }

    public func reload(): Bool {
        let result = loadConfigFile(this.cfg.sourcePath)
        for (w in result.warnings) {
            this.log.warn("config", w)
        }
        if (!result.ok()) {
            for (e in result.errors) {
                this.log.error("config", e)
            }
            this.log.error("config", "配置热重载失败，继续使用旧配置")
            return false
        }
        this.hotkeys.unregisterAll()
        this.cfg = result.snapshot
        this.dispatcher.cfg = result.snapshot
        this.registerHotkeys()
        this.log.info("config", "配置已热重载：" + result.snapshot.summary())
        return true
    }
}
