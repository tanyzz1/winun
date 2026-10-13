package winun.platform

import std.collection.*
import winun.domain.*

// 平台能力抽象：领域层与编排层只依赖这些接口，Win32 细节收敛在其实现里
public interface WindowBackend {
    func listWindows(): ArrayList<WindowInfo>
    func foregroundWindow(): WindowId
    func place(p: Placement, activate: Bool): Bool
    func show(id: WindowId): Bool
    func hide(id: WindowId): Bool
    func minimize(id: WindowId): Bool
    func maximize(id: WindowId): Bool
    func restore(id: WindowId): Bool
    func activate(id: WindowId): Bool
    func workArea(id: WindowId): Rect
    func isAlive(id: WindowId): Bool
}

public interface AppLauncher {
    func launch(spec: AppSpec): Int64
}

public interface HotkeyBackend {
    func register(chord: Chord, id: Int32, action: Action): Bool
    func unregisterAll(): Unit
    func registeredCount(): Int64
}

public interface Clock {
    func nowMs(): Int64
    func sleepMs(ms: Int64): Unit
}

// ---------- 空实现：单元测试与 dry-run 使用 ----------

public class NullWindowBackend <: WindowBackend {
    public init() {}

    public func listWindows(): ArrayList<WindowInfo> { return ArrayList<WindowInfo>() }
    public func foregroundWindow(): WindowId { return WindowId() }
    public func place(p: Placement, activate: Bool): Bool { return true }
    public func show(id: WindowId): Bool { return true }
    public func hide(id: WindowId): Bool { return true }
    public func minimize(id: WindowId): Bool { return true }
    public func maximize(id: WindowId): Bool { return true }
    public func restore(id: WindowId): Bool { return true }
    public func activate(id: WindowId): Bool { return true }
    public func workArea(id: WindowId): Rect { return Rect(left: 0, top: 0, right: 1920, bottom: 1080) }
    public func isAlive(id: WindowId): Bool { return true }
}

public class NullLauncher <: AppLauncher {
    public init() {}
    public func launch(spec: AppSpec): Int64 { return 0 }
}

public class NullHotkeys <: HotkeyBackend {
    public init() {}
    public func register(chord: Chord, id: Int32, action: Action): Bool { return true }
    public func unregisterAll(): Unit {}
    public func registeredCount(): Int64 { return 0 }
}

public class SystemClock <: Clock {
    public init() {}
    public func nowMs(): Int64 { return 0 }
    public func sleepMs(ms: Int64): Unit {}
}
