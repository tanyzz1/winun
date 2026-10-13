package winun.core

import std.collection.*
import winun.domain.*

// 会话状态：当前组、每组上次焦点、统计
public class Session {
    public var activeGroup: String = ""
    public var lastFocused: HashMap<String, WindowId> = HashMap<String, WindowId>()
    public var activations: Int64 = 0

    public init() {}

    public func rememberFocus(group: String, id: WindowId): Unit {
        this.lastFocused[group] = id
    }

    public func lastFocusOf(group: String): Option<WindowId> {
        return this.lastFocused.get(group)
    }
}
