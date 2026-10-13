package winun.core

import std.collection.*
import std.sync.*
import winun.domain.*
import winun.platform.*
import winun.infra.*
import winun.config.*

// 运行期索引：窗口清单、应用归属、组归属
public class Registry {
    let lock = Mutex()
    var windows: ArrayList<WindowInfo> = ArrayList<WindowInfo>()
    var appOfWindow: HashMap<Int64, String> = HashMap<Int64, String>()
    var groupMembers: HashMap<String, ArrayList<WindowId>> = HashMap<String, ArrayList<WindowId>>()

    public init() {}

    public func refresh(backend: WindowBackend, cfg: ConfigSnapshot): Int64 {
        let found = backend.listWindows()
        synchronized(this.lock) {
            this.windows = found
            this.appOfWindow.clear()
            for (w in found) {
                var matched = ""
                for (appId in cfg.appOrder) {
                    let spec = cfg.apps[appId]
                    if (matchesApp(w, spec)) {
                        matched = appId
                        break
                    }
                }
                w.appId = matched
                if (!matched.isEmpty()) {
                    this.appOfWindow.add(w.id.value, matched)
                }
            }
            // 清理已经消失的窗口
            for (g in this.groupMembers.keys()) {
                let kept = ArrayList<WindowId>()
                for (id in this.groupMembers[g]) {
                    if (this.containsWindow(id)) {
                        kept.add(id)
                    }
                }
                this.groupMembers[g] = kept
            }
        }
        return found.size
    }

    func containsWindow(id: WindowId): Bool {
        for (w in this.windows) {
            if (w.id.value == id.value) {
                return true
            }
        }
        return false
    }

    public func all(): ArrayList<WindowInfo> {
        var copy = ArrayList<WindowInfo>()
        synchronized(this.lock) {
            copy = ArrayList<WindowInfo>(this.windows)
        }
        return copy
    }

    public func appIdOf(id: WindowId): String {
        var s = ""
        synchronized(this.lock) {
            match (this.appOfWindow.get(id.value)) {
                case Some(v) => s = v
                case None => s = ""
            }
        }
        return s
    }

    public func windowsOfApp(appId: String): ArrayList<WindowId> {
        let out = ArrayList<WindowId>()
        synchronized(this.lock) {
            for (w in this.windows) {
                if (w.appId == appId) {
                    out.add(w.id)
                }
            }
        }
        return out
    }

    public func adopt(group: String, id: WindowId): Unit {
        synchronized(this.lock) {
            if (!this.groupMembers.contains(group)) {
                this.groupMembers.add(group, ArrayList<WindowId>())
            }
            let list = this.groupMembers[group]
            var exists = false
            for (x in list) {
                if (x.value == id.value) {
                    exists = true
                    break
                }
            }
            if (!exists) {
                list.add(id)
            }
        }
    }

    public func release(id: WindowId): Unit {
        synchronized(this.lock) {
            for (g in this.groupMembers.keys()) {
                let kept = ArrayList<WindowId>()
                for (x in this.groupMembers[g]) {
                    if (x.value != id.value) {
                        kept.add(x)
                    }
                }
                this.groupMembers[g] = kept
            }
        }
    }

    public func membersOf(group: String): ArrayList<WindowId> {
        let out = ArrayList<WindowId>()
        synchronized(this.lock) {
            match (this.groupMembers.get(group)) {
                case Some(list) =>
                    for (x in list) {
                        out.add(x)
                    }
                case None => ()
            }
        }
        return out
    }

    public func groupOf(id: WindowId): String {
        var g = ""
        synchronized(this.lock) {
            for (name in this.groupMembers.keys()) {
                for (x in this.groupMembers[name]) {
                    if (x.value == id.value) {
                        g = name
                    }
                }
            }
        }
        return g
    }
}
