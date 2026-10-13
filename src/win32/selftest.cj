package winun.win32

import std.collection.*
import winun.domain.*
import winun.layout.*
import winun.infra.*

public enum CheckStatus {
    | Passed
    | Failed
    | Skipped
}

public class CheckResult {
    public var name: String = ""
    public var status: CheckStatus = CheckStatus.Failed
    public var detail: String = ""

    public init(name: String, status: CheckStatus, detail: String) {
        this.name = name
        this.status = status
        this.detail = detail
    }
}

public func statusName(s: CheckStatus): String {
    match (s) {
        case CheckStatus.Passed => "PASS"
        case CheckStatus.Failed => "FAIL"
        case CheckStatus.Skipped => "SKIP"
    }
}

func check(name: String, ok: Bool, detail: String): CheckResult {
    return CheckResult(name, if (ok) { CheckStatus.Passed } else { CheckStatus.Failed }, detail)
}

func joinList(items: ArrayList<String>): String {
    var s = ""
    for (i in 0..items.size) {
        if (i > 0) {
            s = s + "、"
        }
        s = s + items[i]
    }
    return s
}

func near(a: Int32, b: Int32): Bool {
    let d = a - b
    return d <= 2 && d >= -2
}

func rectClose(a: Rect, b: Rect): Bool {
    return near(a.left, b.left) && near(a.top, b.top) && near(a.right, b.right) && near(a.bottom, b.bottom)
}

// 自检：不需要其它进程的窗口，也不需要全局热键即可验证大部分平台写路径
public func runSelfTest(): ArrayList<CheckResult> {
    let out = ArrayList<CheckResult>()

    // 1) 结构体 ABI 断言（FFI 最危险的错误类型）
    out.add(check("ABI RECTC == 16", sizeOf<RECTC>() == 16, "sizeOf=" + sizeOf<RECTC>().toString()))
    out.add(check("ABI POINT == 8", sizeOf<POINT>() == 8, "sizeOf=" + sizeOf<POINT>().toString()))
    out.add(check("ABI MSG == 48", sizeOf<MSG>() == 48, "sizeOf=" + sizeOf<MSG>().toString()))
    out.add(check("ABI MONITORINFO == 40", sizeOf<MONITORINFO>() == 40, "sizeOf=" + sizeOf<MONITORINFO>().toString()))
    out.add(check("ABI STARTUPINFOW == 104", sizeOf<STARTUPINFOW>() == 104, "sizeOf=" + sizeOf<STARTUPINFOW>().toString()))
    out.add(check("ABI PROCESS_INFORMATION == 24", sizeOf<PROCESS_INFORMATION>() == 24, "sizeOf=" + sizeOf<PROCESS_INFORMATION>().toString()))
    out.add(check("ABI WNDCLASSEXW == 80", sizeOf<WNDCLASSEXW>() == 80, "sizeOf=" + sizeOf<WNDCLASSEXW>().toString()))

    // 2) 自建窗口 + 真实 backend 的布局执行闭环
    let h1 = createProbeWindow("winun selftest #1", 40, 40, 300, 200)
    let h2 = createProbeWindow("winun selftest #2", 400, 40, 300, 200)
    if (h1.isNull() || h2.isNull()) {
        out.add(CheckResult("创建探针窗口", CheckStatus.Failed, "CreateWindowExW 返回空句柄"))
        return out
    }
    out.add(CheckResult("创建探针窗口", CheckStatus.Passed, "两个隐藏窗口已创建"))

    let backend = Win32WindowBackend()
    let id1 = registerHandle(h1)
    let id2 = registerHandle(h2)

    // 工作区用一个合成的矩形，避免受真实显示器与任务栏影响
    let area = Rect(left: 0, top: 0, right: 1000, bottom: 600)

    let grid = LayoutSpec()
    grid.kind = LayoutKind.Grid
    grid.columns = 2
    grid.rows = 1
    grid.gap = 0
    grid.margins = Margins()
    let placements = solve([id1, id2], grid, area)
    var placeOk = true
    var placeDetail = ""
    for (p in placements) {
        if (!backend.place(p, false)) {
            placeOk = false
        }
        let actual = windowRectOf(toHwnd(p.window))
        if (!rectClose(actual, p.rect)) {
            placeOk = false
            placeDetail = placeDetail + " " + p.window.describe() + " 期望" + p.rect.describe() + " 实际" + actual.describe()
        }
    }
    out.add(check("grid 布局执行（solve -> SetWindowPos -> 读回校验）", placeOk,
        if (placeOk) { "两个窗口各占半屏：0..500 / 500..1000" } else { placeDetail }))

    // 3) anchor 布局执行
    let anchor = LayoutSpec()
    anchor.kind = LayoutKind.Anchor
    anchor.anchor = AnchorKind.Right
    anchor.sizePercent = Some(Size(width: 50, height: 100))
    let snaps = solve([id1], anchor, area)
    var anchorOk = false
    if (snaps.size == 1) {
        backend.place(snaps[0], false)
        anchorOk = rectClose(windowRectOf(h1), snaps[0].rect)
    }
    out.add(check("anchor 贴边执行（右半屏）", anchorOk,
        if (anchorOk) { "窗口贴到 " + windowRectOf(h1).describe() } else { "实际 " + windowRectOf(h1).describe() }))

    // 4) 窗口可见性与最小化往返（对自己窗口）
    var stateOk = false
    var stateDetail = "ShowWindow 返回值异常"
    if (backend.show(id1)) {
        let visible = unsafe { IsWindowVisible(h1) }
        if (backend.minimize(id1)) {
            let iconic = unsafe { IsIconic(h1) }
            stateOk = visible && iconic
            stateDetail = "visible=" + visible.toString() + " minimized=" + iconic.toString()
        }
    }
    out.add(check("ShowWindow / IsWindowVisible / IsIconic", stateOk, stateDetail))

    // 5) 窗口描述（枚举信息的读取路径）
    let info = backend.describe(id2)
    var descOk = false
    var descDetail = "describe 返回空"
    match (info) {
        case Some(w) =>
            descOk = w.className == PROBE_CLASS && w.exeName.toAsciiLower() == "main.exe"
            descDetail = "class=" + w.className + " exe=" + w.exeName + " pid=" + w.pid.toString()
        case None => ()
    }
    out.add(check("窗口识别（类名/进程路径）", descOk, descDetail))

    // 6) 显示器工作区读取
    let wa = backend.workArea(id2)
    out.add(check("显示器工作区读取", wa.width() > 0 && wa.height() > 0, "workArea=" + wa.describe()))

    // 7) 全局热键：逐個尝试候选组合键，用于区分"环境不允许"与"该组合键已被占用"
    let hotkeys = Win32Hotkeys()
    let candidates: Array<(String, UInt32, UInt32)> = [
        ("win+alt+f11", MOD_WIN | MOD_ALT, 0x7A),
        ("win+alt+f12", MOD_WIN | MOD_ALT, 0x7B),
        ("ctrl+alt+f11", MOD_CONTROL | MOD_ALT, 0x7A)
    ]
    var id: Int32 = 1
    let free = ArrayList<String>()
    let taken = ArrayList<String>()
    for (c in candidates) {
        let chord = Chord(modifiers: c[1], vk: c[2], text: c[0])
        if (hotkeys.register(chord, id, Action.Quit)) {
            free.add(c[0])
            id = id + 1
        } else {
            taken.add(c[0])
        }
    }
    hotkeys.unregisterAll()
    if (free.size > 0) {
        out.add(CheckResult("全局热键注册", CheckStatus.Passed,
            "可注册：" + joinList(free) + (if (taken.size > 0) { "；被占用：" + joinList(taken) } else { "" })))
    } else {
        out.add(CheckResult("全局热键注册", CheckStatus.Skipped,
            "候选组合键全部注册失败：可能是环境限制，也可能是都被占用（本环境下 GetLastError 不可用，无法区分）"))
    }

    // 7b) 热键消息闭环：注册 → 自投递 WM_HOTKEY → 消息循环取回（不依赖真实按键）
    let loopId: Int32 = 77
    let loopChord = Chord(modifiers: MOD_WIN | MOD_ALT, vk: 0x7B, text: "win+alt+f12")
    if (hotkeys.register(loopChord, loopId, Action.Quit)) {
        var got = false
        var gotDetail = "未取到消息"
        if (postThreadHotkey(currentThreadId(), loopId)) {
            // 队列里可能先有其它消息（例如 0x799），需要循环取到 WM_HOTKEY 为止；
            // 用 PeekMessageW 先确认队列非空，避免 GetMessageW 阻塞导致自检挂死
            var attempts = 0
            while (attempts < 20 && !got) {
                if (!hasAnyMessage()) {
                    sleepMs(50)
                    attempts = attempts + 1
                    continue
                }
                let pumped = pumpMessage()
                if (pumped.result <= 0) {
                    gotDetail = "消息循环返回 " + pumped.result.toString()
                    break
                }
                if (pumped.isHotkey() && pumped.hotkeyId() == loopId) {
                    got = true
                    gotDetail = "收到 WM_HOTKEY id=" + loopId.toString() + "（第 " + (attempts + 1).toString() + " 次取消息）"
                } else {
                    gotDetail = "已跳过 message=0x" + pumped.msg.message.toString()
                    translateMessage(pumped.msg)
                    dispatchMessage(pumped.msg)
                    attempts = attempts + 1
                }
            }
            if (!got && gotDetail.isEmpty()) {
                gotDetail = "20 次内未取到 WM_HOTKEY"
            }
        } else {
            gotDetail = "PostThreadMessageW 失败"
        }
        hotkeys.unregisterAll()
        out.add(check("热键消息闭环（注册 → 自投递 WM_HOTKEY → 消息循环取回）", got, gotDetail))
    } else {
        out.add(CheckResult("热键消息闭环（注册 → 自投递 WM_HOTKEY → 消息循环取回）", CheckStatus.Skipped,
            "该组合键注册失败，无法验证消息闭环"))
    }

    // 8) 消息队列与前台窗口读取
    out.add(check("线程消息队列", ensureMessageQueue(), "PeekMessageW 正常"))
    let fg = backend.foregroundWindow()
    out.add(CheckResult("前台窗口读取", if (fg.isNull()) { CheckStatus.Failed } else { CheckStatus.Passed },
        "foreground=" + fg.describe()))

    destroyProbeWindow(h1)
    destroyProbeWindow(h2)
    return out
}
