package winun.config

import std.collection.*
import winun.domain.*
import winun.infra.*

public class HotkeyBinding {
    public var chordText: String = ""
    public var chord: Chord = Chord()
    public var action: Action = Action.Quit
    public var actionText: String = ""

    public init() {}

    public func describe(): String {
        return this.chordText + " -> " + this.actionText
    }
}

public class ConfigSnapshot {
    public var version: Int64 = 1
    public var sourcePath: String = ""
    public var logLevel: LogLevel = LogLevel.Info
    public var logFile: String = ""
    public var logRotateKb: Int64 = 2048
    public var watchConfig: Bool = true
    public var strict: Bool = false
    public var startupGroup: String = ""
    public var defaultLayout: String = ""
    public var commandTimeoutMs: Int64 = 150
    public var hotkeys: ArrayList<HotkeyBinding> = ArrayList<HotkeyBinding>()
    public var apps: HashMap<String, AppSpec> = HashMap<String, AppSpec>()
    public var launches: HashMap<String, LaunchSpec> = HashMap<String, LaunchSpec>()
    public var layouts: HashMap<String, LayoutSpec> = HashMap<String, LayoutSpec>()
    public var groups: HashMap<String, GroupDef> = HashMap<String, GroupDef>()
    // 组与启动集合保持声明顺序（JSON 对象无序，这里由解析顺序决定）
    public var groupOrder: ArrayList<String> = ArrayList<String>()
    public var launchOrder: ArrayList<String> = ArrayList<String>()
    public var appOrder: ArrayList<String> = ArrayList<String>()
    public var layoutOrder: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func summary(): String {
        return "apps=" + this.apps.size.toString() + " launches=" + this.launches.size.toString() +
            " layouts=" + this.layouts.size.toString() + " groups=" + this.groups.size.toString() +
            " hotkeys=" + this.hotkeys.size.toString()
    }
}

public class LoadResult {
    public var snapshot: ConfigSnapshot = ConfigSnapshot()
    public var errors: ArrayList<String> = ArrayList<String>()
    public var warnings: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func ok(): Bool {
        return this.errors.size == 0
    }
}
