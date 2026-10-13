package winun.core

import std.collection.*
import winun.domain.*
import winun.layout.*
import winun.platform.*
import winun.infra.*
import winun.config.*

// 动作执行器：把配置里的动作落到窗口上
public class Dispatcher {
    let backend: WindowBackend
    let launcher: AppLauncher
    let hotkeys: HotkeyBackend
    let clock: Clock
    let log: Logger
    public var cfg: ConfigSnapshot
    public var registry: Registry
    public var session: Session
    public var shouldQuit: Bool = false
    public var reloadRequested: Bool = false

    public init(backend: WindowBackend, launcher: AppLauncher, hotkeys: HotkeyBackend,
                clock: Clock, cfg: ConfigSnapshot, log: Logger) {
        this.backend = backend
        this.launcher = launcher
        this.hotkeys = hotkeys
        this.clock = clock
        this.log = log
        this.cfg = cfg
        this.registry = Registry()
        this.session = Session()
    }

    public func dispatch(action: Action): Unit {
        this.log.debug("dispatcher", "执行动作：" + describeAction(action))
        match (action) {
            case Action.Launch(id) => this.launchSet(id)
            case Action.GroupActivate(id) => this.activateGroup(id)
            case Action.GroupCycleNext => this.cycleGroup(1)
            case Action.GroupCyclePrev => this.cycleGroup(-1)
            case Action.WindowToGroup(target) =>
                let group = if (target == "current") { this.session.activeGroup } else { target }
                let fg = this.backend.foregroundWindow()
                if (group.isEmpty()) {
                    this.log.warn("dispatcher", "当前没有活动组，无法收编窗口")
                } else if (fg.isNull()) {
                    this.log.warn("dispatcher", "没有前台窗口可收编")
                } else {
                    this.registry.adopt(group, fg)
                    this.log.info("dispatcher", "窗口 " + fg.describe() + " 已收编进组 " + group)
                    this.applyLayout(group)
                }
            case Action.WindowRemoveFromGroup =>
                let fg = this.backend.foregroundWindow()
                this.registry.release(fg)
                this.log.info("dispatcher", "窗口 " + fg.describe() + " 已移出所属组")
            case Action.LayoutApply(target) =>
                let group = if (target == "current") { this.session.activeGroup } else { target }
                if (group.isEmpty()) {
                    this.log.warn("dispatcher", "没有可应用布局的组")
                } else {
                    this.applyLayout(group)
                }
            case Action.WindowSnap(t) => this.snapForeground(t)
            case Action.WindowMaximize =>
                let fg = this.backend.foregroundWindow()
                this.backend.maximize(fg)
            case Action.WindowRestore =>
                let fg = this.backend.foregroundWindow()
                this.backend.restore(fg)
            case Action.WindowFloatToggle =>
                this.log.info("dispatcher", "float toggle 暂未实现（P2）")
            case Action.WindowFocusCycle =>
                this.log.info("dispatcher", "focus-cycle 暂未实现（P2）")
            case Action.ConfigReload => this.reloadRequested = true
            case Action.Quit => this.shouldQuit = true
        }
    }

    // ---------- 启动集合 ----------

    public func launchSet(id: String): Unit {
        match (this.cfg.launches.get(id)) {
            case None =>
                this.log.error("dispatcher", "未定义的启动集合 " + id)
            case Some(l) =>
                let targetGroup = if (!l.group.isEmpty()) { l.group } else { this.session.activeGroup }
                for (appId in l.apps) {
                    match (this.cfg.apps.get(appId)) {
                        case None => this.log.error("dispatcher", "启动集合引用了不存在的应用 " + appId)
                        case Some(spec) =>
                            let existing = this.registry.windowsOfApp(appId)
                            var reuseExisting = false
                            match (spec.reuse) {
                                case ReusePolicy.Existing => reuseExisting = true
                                case ReusePolicy.New => ()
                            }
                            if (reuseExisting && existing.size > 0) {
                                this.log.info("dispatcher", appId + " 已有实例（" + existing.size.toString() + " 个窗口），直接复用")
                                for (w in existing) {
                                    this.adoptInto(targetGroup, w)
                                }
                            } else {
                                let pid = this.launcher.launch(spec)
                                if (pid == 0) {
                                    this.log.error("dispatcher", appId + " 启动失败：" + spec.exe)
                                } else {
                                    this.log.info("dispatcher", appId + " 已启动 pid=" + pid.toString())
                                }
                                this.waitForWindow(appId, spec.startupWaitMs, targetGroup)
                                if (l.staggerMs > 0) {
                                    this.clock.sleepMs(l.staggerMs)
                                }
                            }
                    }
                }
                if (!l.group.isEmpty()) {
                    this.activateGroup(l.group)
                } else if (!targetGroup.isEmpty()) {
                    this.applyLayout(targetGroup)
                }
        }
    }

    func adoptInto(group: String, id: WindowId): Unit {
        if (!group.isEmpty()) {
            this.registry.adopt(group, id)
        }
    }

    func waitForWindow(appId: String, timeoutMs: Int64, group: String): Unit {
        var waited: Int64 = 0
        var found = false
        while (waited < timeoutMs) {
            this.registry.refresh(this.backend, this.cfg)
            let ws = this.registry.windowsOfApp(appId)
            if (ws.size > 0) {
                for (w in ws) {
                    this.adoptInto(group, w)
                }
                found = true
                this.log.info("dispatcher", appId + " 窗口已出现（" + ws.size.toString() + " 个）")
                break
            }
            this.clock.sleepMs(200)
            waited = waited + 200
        }
        if (!found) {
            this.log.warn("dispatcher", appId + " 在 " + timeoutMs.toString() + "ms 内未出现窗口")
        }
    }

    func cycleGroup(step: Int64): Unit {
        let order = this.cfg.groupOrder
        if (order.size == 0) {
            this.log.warn("dispatcher", "配置里没有定义任何组")
            return
        }
        var index: Int64 = 0
        if (!this.session.activeGroup.isEmpty()) {
            for (i in 0..order.size) {
                if (order[i] == this.session.activeGroup) {
                    index = i
                }
            }
        }
        var next = index + step
        if (next < 0) {
            next = order.size - 1
        }
        if (next >= order.size) {
            next = 0
        }
        this.activateGroup(order[next])
    }

    func activateGroup(id: String): Unit {
        match (this.cfg.groups.get(id)) {
            case None =>
                this.log.error("dispatcher", "未定义的组 " + id)
            case Some(g) =>
                let previous = this.session.activeGroup
                if (!previous.isEmpty() && previous != id) {
                    this.leaveGroup(previous)
                }
                this.session.activeGroup = id
                this.session.activations = this.session.activations + 1
                let members = this.registry.membersOf(id)
                for (m in members) {
                    match (g.onActivate) {
                        case RestorePolicy.Restore => this.backend.show(m)
                        case RestorePolicy.KeepSize => ()
                    }
                }
                this.applyLayout(id)
                this.focusGroup(id, g, members)
        }
    }

    func leaveGroup(id: String): Unit {
        match (this.cfg.groups.get(id)) {
            case None => ()
            case Some(g) =>
                let focused = this.backend.foregroundWindow()
                if (!focused.isNull()) {
                    this.session.rememberFocus(id, focused)
                }
                for (m in this.registry.membersOf(id)) {
                    match (g.onSwitchAway) {
                        case SwitchAwayPolicy.Minimize => this.backend.minimize(m)
                        case SwitchAwayPolicy.Hide => this.backend.hide(m)
                        case SwitchAwayPolicy.Keep => ()
                    }
                }
        }
    }

    func focusGroup(id: String, g: GroupDef, members: ArrayList<WindowId>): Unit {
        if (members.size == 0) {
            return
        }
        var target = members[0]
        match (g.activate) {
            case ActivatePolicy.FocusFirst => target = members[0]
            case ActivatePolicy.FocusLast =>
                match (this.session.lastFocusOf(id)) {
                    case Some(last) =>
                        for (m in members) {
                            if (m.value == last.value) {
                                target = m
                            }
                        }
                    case None => target = members[0]
                }
            case ActivatePolicy.Cycle =>
                let current = this.backend.foregroundWindow()
                var nextIndex: Int64 = 0
                for (i in 0..members.size) {
                    if (members[i].value == current.value) {
                        nextIndex = i + 1
                    }
                }
                if (nextIndex >= members.size) {
                    nextIndex = 0
                }
                target = members[nextIndex]
        }
        this.backend.activate(target)
        this.session.rememberFocus(id, target)
    }

    // ---------- 布局 ----------

    public func applyLayout(groupId: String): Unit {
        let members = this.registry.membersOf(groupId)
        if (members.size == 0) {
            this.log.warn("dispatcher", "组 " + groupId + " 没有可布局的窗口")
            return
        }
        let spec = this.layoutOf(groupId)
        let area = this.backend.workArea(members[0])
        let placements = solve(members.toArray(), spec, area)
        var applied: Int64 = 0
        for (p in placements) {
            if (this.backend.place(p, false)) {
                applied = applied + 1
            } else {
                this.log.warn("dispatcher", "窗口 " + p.window.describe() + " 布局失败")
            }
        }
        this.log.info("dispatcher", "组 " + groupId + " 应用布局 " + spec.id + "：" +
            applied.toString() + "/" + placements.size.toString() + " 个窗口")
    }

    func layoutOf(groupId: String): LayoutSpec {
        var layoutId = ""
        match (this.cfg.groups.get(groupId)) {
            case Some(g) => layoutId = g.layoutId
            case None => ()
        }
        if (layoutId.isEmpty()) {
            layoutId = this.cfg.defaultLayout
        }
        match (this.cfg.layouts.get(layoutId)) {
            case Some(l) => l
            case None =>
                let fallback = LayoutSpec()
                fallback.id = "(内置默认)"
                fallback.kind = LayoutKind.Grid
                fallback.columns = 2
                fallback.rows = 1
                fallback.gap = 8
                fallback.margins = Margins(left: 8, top: 8, right: 8, bottom: 8)
                fallback
        }
    }

    // ---------- 单窗口操作 ----------

    func snapForeground(t: SnapTarget): Unit {
        let fg = this.backend.foregroundWindow()
        if (fg.isNull()) {
            return
        }
        let area = this.backend.workArea(fg)
        let spec = LayoutSpec()
        spec.id = "(snap)"
        spec.kind = LayoutKind.Anchor
        match (t) {
            case SnapTarget.LeftHalf =>
                spec.anchor = AnchorKind.Left
                spec.sizePercent = Some(Size(width: 50, height: 100))
            case SnapTarget.RightHalf =>
                spec.anchor = AnchorKind.Right
                spec.sizePercent = Some(Size(width: 50, height: 100))
            case SnapTarget.TopHalf =>
                spec.anchor = AnchorKind.Top
                spec.sizePercent = Some(Size(width: 100, height: 50))
            case SnapTarget.BottomHalf =>
                spec.anchor = AnchorKind.Bottom
                spec.sizePercent = Some(Size(width: 100, height: 50))
        }
        let placements = solve([fg], spec, area)
        for (p in placements) {
            this.backend.place(p, false)
        }
    }
}
