package winun.domain

import std.collection.*

public struct Rect {
    public var left: Int32 = 0
    public var top: Int32 = 0
    public var right: Int32 = 0
    public var bottom: Int32 = 0

    public init(left!: Int32 = 0, top!: Int32 = 0, right!: Int32 = 0, bottom!: Int32 = 0) {
        this.left = left
        this.top = top
        this.right = right
        this.bottom = bottom
    }

    public func width(): Int32 { return this.right - this.left }
    public func height(): Int32 { return this.bottom - this.top }
    public func isEmpty(): Bool { return this.right <= this.left || this.bottom <= this.top }
    public func describe(): String {
        return "(" + this.left.toString() + "," + this.top.toString() + "," +
            this.right.toString() + "," + this.bottom.toString() + ")"
    }
}

public struct Size {
    public var width: Int32 = 0
    public var height: Int32 = 0

    public init(width!: Int32 = 0, height!: Int32 = 0) {
        this.width = width
        this.height = height
    }
}

public struct Margins {
    public var left: Int32 = 0
    public var top: Int32 = 0
    public var right: Int32 = 0
    public var bottom: Int32 = 0

    public init(left!: Int32 = 0, top!: Int32 = 0, right!: Int32 = 0, bottom!: Int32 = 0) {
        this.left = left
        this.top = top
        this.right = right
        this.bottom = bottom
    }
}

// 窗口身份：领域层不出现 Win32 类型，句柄被压成不透明整数
public struct WindowId {
    public var value: Int64 = 0

    public init(value!: Int64 = 0) {
        this.value = value
    }

    public func isNull(): Bool { return this.value == 0 }
    public func describe(): String { return "0x" + this.value.toString() }
}

public enum WindowState {
    | Normal
    | Maximized
    | Minimized
    | Hidden
}

public struct Placement {
    public var window: WindowId = WindowId()
    public var rect: Rect = Rect()
    public var state: WindowState = WindowState.Normal

    public init(window!: WindowId = WindowId(), rect!: Rect = Rect(), state!: WindowState = WindowState.Normal) {
        this.window = window
        this.rect = rect
        this.state = state
    }
}

public class WindowInfo {
    public var id: WindowId = WindowId()
    public var pid: UInt32 = 0
    public var exePath: String = ""
    public var exeName: String = ""
    public var className: String = ""
    public var title: String = ""
    public var rect: Rect = Rect()
    public var monitor: Int64 = 0
    public var visible: Bool = true
    public var minimized: Bool = false
    public var appId: String = ""

    public init() {}

    public func describe(): String {
        return this.id.describe() + " pid=" + this.pid.toString() + " exe=" + this.exeName +
            " class=" + this.className + " title=\"" + this.title + "\" rect=" + this.rect.describe()
    }
}

public enum LayoutKind {
    | Grid
    | Ratio
    | Absolute
    | Anchor
}

public func layoutKindName(k: LayoutKind): String {
    match (k) {
        case LayoutKind.Grid => "grid"
        case LayoutKind.Ratio => "ratio"
        case LayoutKind.Absolute => "absolute"
        case LayoutKind.Anchor => "anchor"
    }
}

public enum MonitorSelector {
    | Primary
    | Secondary
    | Index(Int64)
}

public enum OrderPolicy {
    | Listed
    | ZOrder
    | Title
}

public enum AnchorKind {
    | Left
    | Right
    | Top
    | Bottom
    | TopLeft
    | TopRight
    | BottomLeft
    | BottomRight
    | Center
}

public func anchorKindName(a: AnchorKind): String {
    match (a) {
        case AnchorKind.Left => "left"
        case AnchorKind.Right => "right"
        case AnchorKind.Top => "top"
        case AnchorKind.Bottom => "bottom"
        case AnchorKind.TopLeft => "top-left"
        case AnchorKind.TopRight => "top-right"
        case AnchorKind.BottomLeft => "bottom-left"
        case AnchorKind.BottomRight => "bottom-right"
        case AnchorKind.Center => "center"
    }
}

public class LayoutSpec {
    public var id: String = ""
    public var kind: LayoutKind = LayoutKind.Grid
    public var columns: Int64 = 1
    public var rows: Int64 = 1
    public var gap: Int32 = 8
    public var margins: Margins = Margins()
    public var ratios: Array<Float64> = []
    public var cells: Array<Rect> = []
    public var monitor: MonitorSelector = MonitorSelector.Primary
    public var order: OrderPolicy = OrderPolicy.Listed
    public var anchor: AnchorKind = AnchorKind.Left
    public var sizePercent: Option<Size> = None
    public var overflowOffset: Int32 = 32

    public init() {}

    public func describe(): String {
        return this.id + " type=" + layoutKindName(this.kind) + " cols=" + this.columns.toString() +
            " rows=" + this.rows.toString() + " gap=" + this.gap.toString()
    }
}

public enum ActivatePolicy {
    | FocusLast
    | FocusFirst
    | Cycle
}

public enum SwitchAwayPolicy {
    | Minimize
    | Hide
    | Keep
}

public enum RestorePolicy {
    | Restore
    | KeepSize
}

public class GroupDef {
    public var id: String = ""
    public var name: String = ""
    public var layoutId: String = ""
    public var appIds: Array<String> = []
    public var monitor: MonitorSelector = MonitorSelector.Primary
    public var activate: ActivatePolicy = ActivatePolicy.FocusLast
    public var onSwitchAway: SwitchAwayPolicy = SwitchAwayPolicy.Minimize
    public var onActivate: RestorePolicy = RestorePolicy.Restore

    public init() {}

    public func describe(): String {
        return this.id + " (" + this.name + ") layout=" + this.layoutId + " apps=" + this.appIds.size.toString()
    }
}

public enum ReusePolicy {
    | Existing
    | New
}

public class AppSpec {
    public var id: String = ""
    public var exe: String = ""
    public var args: Array<String> = []
    public var cwd: String = ""
    public var env: Array<(String, String)> = []
    public var matchExe: String = ""
    public var matchPath: String = ""
    public var matchClass: String = ""
    public var matchTitle: String = ""
    public var startupWaitMs: Int64 = 8000
    public var reuse: ReusePolicy = ReusePolicy.New
    public var maximizeOnStart: Bool = false

    public init() {}

    // 命令行：exe + 参数（用双引号包裹含空格的参数）
    public func commandLine(): String {
        var s = "\"" + this.exe + "\""
        for (a in this.args) {
            s = s + " " + (if (a.contains(" ")) { "\"" + a + "\"" } else { a })
        }
        return s
    }

    public func describe(): String {
        return this.id + " exe=" + this.exe + " match(exe=" + this.matchExe + ", title=" + this.matchTitle + ")"
    }
}

public class LaunchSpec {
    public var id: String = ""
    public var apps: Array<String> = []
    public var staggerMs: Int64 = 300
    public var group: String = ""
    public var layout: String = ""

    public init() {}

    public func describe(): String {
        return this.id + " apps=" + this.apps.size.toString() + " group=" + this.group
    }
}
