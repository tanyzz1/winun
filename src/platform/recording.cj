package winun.platform

import std.collection.*
import winun.domain.*
import winun.infra.*

// 记录型后端：让编排逻辑（组切换、启动集合、布局应用）可以在无窗口环境下完整单测
public class RecordingWindowBackend <: WindowBackend {
    public var windows: ArrayList<WindowInfo> = ArrayList<WindowInfo>()
    public var placed: ArrayList<Placement> = ArrayList<Placement>()
    public var shown: ArrayList<Int64> = ArrayList<Int64>()
    public var hidden: ArrayList<Int64> = ArrayList<Int64>()
    public var minimized: ArrayList<Int64> = ArrayList<Int64>()
    public var maximized: ArrayList<Int64> = ArrayList<Int64>()
    public var restored: ArrayList<Int64> = ArrayList<Int64>()
    public var activated: ArrayList<Int64> = ArrayList<Int64>()
    public var area: Rect = Rect(left: 0, top: 0, right: 1920, bottom: 1080)
    public var foreground: WindowId = WindowId()
    var nextId: Int64 = 100

    public init() {}

    // 造一个窗口：exe 名用于匹配配置里的 match.exe
    public func addWindow(exeName: String, title: String): WindowId {
        let w = WindowInfo()
        w.id = WindowId(value: this.nextId)
        this.nextId = this.nextId + 1
        w.exeName = exeName
        w.exePath = "C:\\apps\\" + exeName
        w.className = "TestWindowClass"
        w.title = title
        w.visible = true
        w.pid = UInt32(w.id.value)
        this.windows.add(w)
        return w.id
    }

    public func listWindows(): ArrayList<WindowInfo> {
        return ArrayList<WindowInfo>(this.windows)
    }

    public func foregroundWindow(): WindowId { return this.foreground }

    public func place(p: Placement, activate: Bool): Bool {
        this.placed.add(p)
        return true
    }

    public func show(id: WindowId): Bool { this.shown.add(id.value); return true }
    public func hide(id: WindowId): Bool { this.hidden.add(id.value); return true }
    public func minimize(id: WindowId): Bool { this.minimized.add(id.value); return true }
    public func maximize(id: WindowId): Bool { this.maximized.add(id.value); return true }
    public func restore(id: WindowId): Bool { this.restored.add(id.value); return true }
    public func activate(id: WindowId): Bool { this.activated.add(id.value); return true }
    public func workArea(id: WindowId): Rect { return this.area }
    public func isAlive(id: WindowId): Bool { return true }

    // 断言辅助
    public func placementsForGroup(): ArrayList<Rect> {
        let out = ArrayList<Rect>()
        for (p in this.placed) {
            out.add(p.rect)
        }
        return out
    }

    public func clearCalls(): Unit {
        this.placed = ArrayList<Placement>()
        this.shown = ArrayList<Int64>()
        this.hidden = ArrayList<Int64>()
        this.minimized = ArrayList<Int64>()
        this.maximized = ArrayList<Int64>()
        this.restored = ArrayList<Int64>()
        this.activated = ArrayList<Int64>()
    }
}

public class RecordingLauncher <: AppLauncher {
    public var launched: ArrayList<String> = ArrayList<String>()
    // 指向后端：启动时"真的"新增一个窗口，以便 dispatcher 的等待窗口逻辑能命中
    public var backend: Option<RecordingWindowBackend> = None
    public var exeOfApp: HashMap<String, String> = HashMap<String, String>()

    public init() {}

    public func register(appId: String, exeName: String): Unit {
        this.exeOfApp.add(appId, exeName)
    }

    public func launch(spec: AppSpec): Int64 {
        this.launched.add(spec.id)
        match (this.backend) {
            case Some(b) =>
                let exe = match (this.exeOfApp.get(spec.id)) {
                    case Some(e) => e
                    case None => spec.id + ".exe"
                }
                let _ = b.addWindow(exe, spec.id + " window")
            case None => ()
        }
        return 4242
    }
}

public class RecordingHotkeys <: HotkeyBackend {
    public var registered: ArrayList<String> = ArrayList<String>()
    public var unregisterCalls: Int64 = 0
    public var failAll: Bool = false

    public init() {}

    public func register(chord: Chord, id: Int32, action: Action): Bool {
        if (this.failAll) {
            return false
        }
        this.registered.add(chord.text)
        return true
    }

    public func unregisterAll(): Unit {
        this.unregisterCalls = this.unregisterCalls + 1
        this.registered = ArrayList<String>()
    }

    public func registeredCount(): Int64 { return this.registered.size }
}

public class FakeClock <: Clock {
    public var sleptMs: Int64 = 0
    public init() {}
    public func nowMs(): Int64 { return 0 }
    public func sleepMs(ms: Int64): Unit { this.sleptMs = this.sleptMs + ms }
}
