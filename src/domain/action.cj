package winun.domain

import std.collection.*

public enum SnapTarget {
    | LeftHalf
    | RightHalf
    | TopHalf
    | BottomHalf
}

public enum Action {
    | Launch(String)
    | GroupActivate(String)
    | GroupCycleNext
    | GroupCyclePrev
    | WindowToGroup(String)
    | WindowRemoveFromGroup
    | LayoutApply(String)
    | WindowSnap(SnapTarget)
    | WindowMaximize
    | WindowRestore
    | WindowFloatToggle
    | WindowFocusCycle
    | ConfigReload
    | Quit
}

public func describeAction(a: Action): String {
    match (a) {
        case Action.Launch(id) => "launch " + id
        case Action.GroupActivate(id) => "group activate " + id
        case Action.GroupCycleNext => "group cycle next"
        case Action.GroupCyclePrev => "group cycle prev"
        case Action.WindowToGroup(id) => "window to-group " + id
        case Action.WindowRemoveFromGroup => "window remove-from-group"
        case Action.LayoutApply(id) => "layout apply " + id
        case Action.WindowSnap(t) =>
            match (t) {
                case SnapTarget.LeftHalf => "window snap left-half"
                case SnapTarget.RightHalf => "window snap right-half"
                case SnapTarget.TopHalf => "window snap top-half"
                case SnapTarget.BottomHalf => "window snap bottom-half"
            }
        case Action.WindowMaximize => "window maximize"
        case Action.WindowRestore => "window restore"
        case Action.WindowFloatToggle => "window float toggle"
        case Action.WindowFocusCycle => "window focus-cycle"
        case Action.ConfigReload => "config reload"
        case Action.Quit => "quit"
    }
}

// 解析配置中的动作字符串；返回 (动作, 错误信息)
public func parseAction(text: String): (Option<Action>, String) {
    let parts = splitWords(text)
    if (parts.size == 0) {
        return (None, "动作为空")
    }
    let head = parts[0].toAsciiLower()
    if (head == "launch") {
        if (parts.size != 2) { return (None, "用法：launch <启动集合名>") }
        return (Some(Action.Launch(parts[1])), "")
    }
    if (head == "quit") {
        return (Some(Action.Quit), "")
    }
    if (head == "config") {
        if (parts.size == 2 && parts[1].toAsciiLower() == "reload") {
            return (Some(Action.ConfigReload), "")
        }
        return (None, "用法：config reload")
    }
    if (head == "group") {
        if (parts.size == 3 && parts[1].toAsciiLower() == "activate") {
            return (Some(Action.GroupActivate(parts[2])), "")
        }
        if (parts.size == 3 && parts[1].toAsciiLower() == "cycle") {
            let d = parts[2].toAsciiLower()
            if (d == "next") { return (Some(Action.GroupCycleNext), "") }
            if (d == "prev") { return (Some(Action.GroupCyclePrev), "") }
            return (None, "group cycle 只支持 next / prev")
        }
        return (None, "用法：group activate <组名> | group cycle next|prev")
    }
    if (head == "layout") {
        if (parts.size == 3 && parts[1].toAsciiLower() == "apply") {
            return (Some(Action.LayoutApply(parts[2])), "")
        }
        return (None, "用法：layout apply <布局名|current>")
    }
    if (head == "window") {
        if (parts.size >= 2 && parts[1].toAsciiLower() == "to-group") {
            if (parts.size != 3) { return (None, "用法：window to-group <组名|current>") }
            return (Some(Action.WindowToGroup(parts[2])), "")
        }
        if (parts.size == 2 && parts[1].toAsciiLower() == "remove-from-group") {
            return (Some(Action.WindowRemoveFromGroup), "")
        }
        if (parts.size == 3 && parts[1].toAsciiLower() == "snap") {
            match (parts[2].toAsciiLower()) {
                case "left-half" => return (Some(Action.WindowSnap(SnapTarget.LeftHalf)), "")
                case "right-half" => return (Some(Action.WindowSnap(SnapTarget.RightHalf)), "")
                case "top-half" => return (Some(Action.WindowSnap(SnapTarget.TopHalf)), "")
                case "bottom-half" => return (Some(Action.WindowSnap(SnapTarget.BottomHalf)), "")
                case _ => return (None, "window snap 只支持 left-half / right-half / top-half / bottom-half")
            }
        }
        if (parts.size == 2) {
            match (parts[1].toAsciiLower()) {
                case "maximize" => return (Some(Action.WindowMaximize), "")
                case "restore" => return (Some(Action.WindowRestore), "")
                case _ => return (None, "未知的 window 动作 '" + parts[1] + "'")
            }
        }
        if (parts.size == 3 && parts[1].toAsciiLower() == "float" && parts[2].toAsciiLower() == "toggle") {
            return (Some(Action.WindowFloatToggle), "")
        }
        if (parts.size == 3 && parts[1].toAsciiLower() == "focus-cycle") {
            return (Some(Action.WindowFocusCycle), "")
        }
        return (None, "无法识别的 window 动作")
    }
    return (None, "未知的动作 '" + head + "'")
}

func splitWords(text: String): Array<String> {
    let out = ArrayList<String>()
    var cur = ""
    for (b in text.trimAscii().toArray()) {
        if (b == 0x20 || b == 0x09) {
            if (!cur.isEmpty()) {
                out.add(cur)
                cur = ""
            }
        } else {
            cur = cur + String.fromUtf8([b])
        }
    }
    if (!cur.isEmpty()) {
        out.add(cur)
    }
    return out.toArray()
}
