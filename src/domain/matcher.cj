package winun.domain

import std.regex.*
import winun.infra.*

// 窗口 -> 应用 的识别规则（配置中的 match 段）
public func matchesApp(info: WindowInfo, spec: AppSpec): Bool {
    if (!spec.matchExe.isEmpty()) {
        if (!equalsIgnoreCase(info.exeName, spec.matchExe) && !equalsIgnoreCase(info.exeName, fileNameOf(spec.matchExe))) {
            return false
        }
    }
    if (!spec.matchPath.isEmpty()) {
        if (!wildcardMatch(spec.matchPath, info.exePath)) {
            return false
        }
    }
    if (!spec.matchClass.isEmpty()) {
        if (info.className != spec.matchClass) {
            return false
        }
    }
    if (!spec.matchTitle.isEmpty()) {
        try {
            let re = Regex(spec.matchTitle)
            if (!re.matches(info.title)) {
                return false
            }
        } catch (e: Exception) {
            return false
        }
    }
    return !(spec.matchExe.isEmpty() && spec.matchPath.isEmpty() && spec.matchClass.isEmpty() && spec.matchTitle.isEmpty())
}

// 通配符匹配：只支持 '*'（大小写不敏感）
public func wildcardMatch(pattern: String, text: String): Bool {
    let p = pattern.toAsciiLower()
    let t = text.toAsciiLower()
    if (!p.contains("*")) {
        return p == t
    }
    let parts = p.split("*")
    var pos: Int64 = 0
    var first = true
    for (seg in parts) {
        if (seg.isEmpty()) {
            first = false
            continue
        }
        let idx = indexOfFrom(t, seg, pos)
        if (idx < 0) {
            return false
        }
        if (first && !p.startsWith("*") && idx != 0) {
            return false
        }
        pos = idx + seg.size
        first = false
    }
    if (!p.endsWith("*") && pos != t.size) {
        return false
    }
    return true
}

func indexOfFrom(text: String, needle: String, from: Int64): Int64 {
    let tb = text.toArray()
    let nb = needle.toArray()
    if (nb.size == 0) {
        return from
    }
    var i = from
    while (i + nb.size <= tb.size) {
        var j: Int64 = 0
        var same = true
        while (j < nb.size) {
            if (tb[i + j] != nb[j]) {
                same = false
                break
            }
            j = j + 1
        }
        if (same) {
            return i
        }
        i = i + 1
    }
    return -1
}
