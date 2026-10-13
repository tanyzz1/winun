package winun.win32

import std.collection.*
import std.sync.*
import winun.domain.*
import winun.platform.*
import winun.infra.*

// 枚举回调：CFunc 不能捕获变量，因此上下文放在包级变量里
let gEnumLock = Mutex()
let gEnumResult = ArrayList<WindowId>()

@C
@CallingConv[STDCALL]
func enumWindowsProc(hwnd: HWND, lParam: Int64): Bool {
    let id = registerHandle(hwnd)
    synchronized(gEnumLock) {
        gEnumResult.add(id)
    }
    return true
}

public class Win32WindowBackend <: WindowBackend {
    public init() {}

    public func listWindows(): ArrayList<WindowInfo> {
        synchronized(gEnumLock) {
            gEnumResult.clear()
        }
        unsafe {
            EnumWindows(enumWindowsProc, 0)
        }
        var raw: Array<WindowId> = []
        synchronized(gEnumLock) {
            raw = gEnumResult.toArray()
        }
        let out = ArrayList<WindowInfo>()
        for (id in raw) {
            let info = this.describe(id)
            match (info) {
                case Some(w) => if (isCandidateWindow(w)) { out.add(w) }
                case None => ()
            }
        }
        return out
    }

    public func describe(id: WindowId): Option<WindowInfo> {
        // 见下方 isCandidateWindow：候选=可见 + 有标题 + 非工具窗口 + 非外壳噪声
        let hwnd = toHwnd(id)
        if (hwnd.isNull()) {
            return None
        }
        let w = WindowInfo()
        w.id = id
        w.className = readClassName(hwnd)
        w.title = readWindowText(hwnd)
        w.visible = unsafe { IsWindowVisible(hwnd) }
        w.minimized = unsafe { IsIconic(hwnd) }
        var rect = RECTC()
        if (unsafe { GetWindowRect(hwnd, inout rect) }) {
            w.rect = Rect(left: rect.left, top: rect.top, right: rect.right, bottom: rect.bottom)
        }
        var pid: UInt32 = 0
        unsafe { GetWindowThreadProcessId(hwnd, inout pid) }
        w.pid = pid
        w.exePath = queryProcessPath(pid)
        w.exeName = fileNameOf(w.exePath)
        return Some(w)
    }

    public func foregroundWindow(): WindowId {
        return registerHandle(unsafe { GetForegroundWindow() })
    }

    public func place(p: Placement, activate: Bool): Bool {
        let hwnd = toHwnd(p.window)
        if (hwnd.isNull()) {
            return false
        }
        var flags = SWP_NOZORDER
        if (!activate) {
            flags = flags | SWP_NOACTIVATE
        }
        let r = p.rect
        return unsafe {
            SetWindowPos(hwnd, NULL_HWND, r.left, r.top, r.width(), r.height(), flags)
        }
    }

    // 注意：ShowWindow 的返回值是"调用前是否可见"，不是成功与否，因此这里以调用后的实际状态为准
    public func show(id: WindowId): Bool {
        let hwnd = toHwnd(id)
        if (hwnd.isNull()) {
            return false
        }
        unsafe { ShowWindow(hwnd, SW_RESTORE) }
        return unsafe { IsWindowVisible(hwnd) }
    }

    public func hide(id: WindowId): Bool {
        let hwnd = toHwnd(id)
        if (hwnd.isNull()) {
            return false
        }
        unsafe { ShowWindow(hwnd, SW_HIDE) }
        return !unsafe { IsWindowVisible(hwnd) }
    }

    public func minimize(id: WindowId): Bool {
        let hwnd = toHwnd(id)
        if (hwnd.isNull()) {
            return false
        }
        unsafe { ShowWindow(hwnd, SW_MINIMIZE) }
        return unsafe { IsIconic(hwnd) }
    }

    public func maximize(id: WindowId): Bool {
        let hwnd = toHwnd(id)
        if (hwnd.isNull()) {
            return false
        }
        unsafe { ShowWindow(hwnd, SW_SHOWMAXIMIZED) }
        return unsafe { IsZoomed(hwnd) }
    }

    public func restore(id: WindowId): Bool {
        let hwnd = toHwnd(id)
        if (hwnd.isNull()) {
            return false
        }
        unsafe { ShowWindow(hwnd, SW_RESTORE) }
        return !unsafe { IsIconic(hwnd) }
    }

    public func activate(id: WindowId): Bool {
        let hwnd = toHwnd(id)
        if (hwnd.isNull()) {
            return false
        }
        unsafe { AllowSetForegroundWindow(UInt32(0xFFFFFFFF)) }
        return unsafe { SetForegroundWindow(hwnd) }
    }

    public func workArea(id: WindowId): Rect {
        let hwnd = toHwnd(id)
        var info = MONITORINFO()
        info.cbSize = UInt32(sizeOf<MONITORINFO>())
        let monitor = unsafe { MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) }
        if (unsafe { GetMonitorInfoW(monitor, inout info) }) {
            let r = info.rcWork
            return Rect(left: r.left, top: r.top, right: r.right, bottom: r.bottom)
        }
        return Rect(left: 0, top: 0,
            right: unsafe { GetSystemMetrics(0) }, bottom: unsafe { GetSystemMetrics(1) })
    }

    public func isAlive(id: WindowId): Bool {
        let hwnd = toHwnd(id)
        if (hwnd.isNull()) {
            return false
        }
        return unsafe { IsWindow(hwnd) }
    }
}

// 候选窗口判定：可见、有标题、不是工具窗口、不是外壳噪声窗口
public func isCandidateWindow(w: WindowInfo): Bool {
    if (!w.visible || w.title.isEmpty()) {
        return false
    }
    if (isShellNoiseClass(w.className)) {
        return false
    }
    let hwnd = toHwnd(w.id)
    if (hwnd.isNull()) {
        return false
    }
    let exStyle = unsafe { GetWindowLongPtrW(hwnd, GWL_EXSTYLE) }
    if ((exStyle & WS_EX_TOOLWINDOW) != 0 && (exStyle & WS_EX_APPWINDOW) == 0) {
        return false
    }
    return true
}

func isShellNoiseClass(cls: String): Bool {
    match (cls) {
        case "Shell_TrayWnd" | "Progman" | "WorkerW" | "DummyDWMListenerWindow" |
             "ThumbnailDeviceHelperWnd" | "EdgeUiInputTopWndClass" |
             "Windows.UI.Core.CoreWindow" | "ApplicationFrameInputSinkWindow" |
             "ForegroundStaging" | "MultitaskingViewFrame" |
             "XamlExplorerHostIslandWindow_WASDK" => true
        case _ => false
    }
}

public func readClassName(hwnd: HWND): String {
    var buf = Array<UInt16>(256, repeat: 0)
    let handle = unsafe { acquireArrayRawData(buf) }
    let n = unsafe { GetClassNameW(hwnd, handle.pointer, 256) }
    unsafe { releaseArrayRawData(handle) }
    if (n <= 0) {
        return ""
    }
    return utf16Decode(buf, Int64(n))
}

public func readWindowText(hwnd: HWND): String {
    let len = unsafe { GetWindowTextLengthW(hwnd) }
    if (len <= 0) {
        return ""
    }
    var buf = Array<UInt16>(Int64(len) + 1, repeat: 0)
    let handle = unsafe { acquireArrayRawData(buf) }
    let n = unsafe { GetWindowTextW(hwnd, handle.pointer, len + 1) }
    unsafe { releaseArrayRawData(handle) }
    if (n <= 0) {
        return ""
    }
    return utf16Decode(buf, Int64(n))
}

public func queryProcessPath(pid: UInt32): String {
    if (pid == 0) {
        return ""
    }
    let process = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) }
    if (process.isNull()) {
        return ""
    }
    var buf = Array<UInt16>(1024, repeat: 0)
    var size: UInt32 = 1024
    let handle = unsafe { acquireArrayRawData(buf) }
    let ok = unsafe { QueryFullProcessImageNameW(process, 0, handle.pointer, inout size) }
    unsafe { releaseArrayRawData(handle) }
    unsafe { CloseHandle(process) }
    if (!ok) {
        return ""
    }
    return utf16Decode(buf, Int64(size))
}

// ---------- 应用启动 ----------

public class Win32Launcher <: AppLauncher {
    public init() {}

    public func launch(spec: AppSpec): Int64 {
        if (spec.exe.isEmpty()) {
            return 0
        }
        let cmd = utf16Encode(spec.commandLine())
        let cwdUnits = if (spec.cwd.isEmpty()) { Array<UInt16>() } else { utf16Encode(spec.cwd) }
        var si = STARTUPINFOW()
        si.cb = UInt32(sizeOf<STARTUPINFOW>())
        si.dwFlags = STARTF_USESHOWWINDOW
        si.wShowWindow = UInt16(SW_SHOWNORMAL)
        var pi = PROCESS_INFORMATION()

        let cmdHandle = unsafe { acquireArrayRawData(cmd) }
        var ok = false
        if (cwdUnits.size > 0) {
            let cwdHandle = unsafe { acquireArrayRawData(cwdUnits) }
            ok = unsafe {
                CreateProcessW(CPointer<UInt16>(), cmdHandle.pointer, CPointer<Unit>(), CPointer<Unit>(),
                    false, 0, CPointer<Unit>(), cwdHandle.pointer, inout si, inout pi)
            }
            unsafe { releaseArrayRawData(cwdHandle) }
        } else {
            ok = unsafe {
                CreateProcessW(CPointer<UInt16>(), cmdHandle.pointer, CPointer<Unit>(), CPointer<Unit>(),
                    false, 0, CPointer<Unit>(), CPointer<UInt16>(), inout si, inout pi)
            }
        }
        unsafe { releaseArrayRawData(cmdHandle) }
        if (!ok) {
            return 0
        }
        let pid = Int64(pi.dwProcessId)
        unsafe { CloseHandle(pi.hProcess) }
        unsafe { CloseHandle(pi.hThread) }
        return pid
    }
}

// ---------- 热键 ----------

public class Win32Hotkeys <: HotkeyBackend {
    // 记录真正注册成功的 id：注册是逐个尝试的，失败的 id 会造成空洞，
    // 按"成功数量"顺序注销会漏掉后面的热键
    let ids = ArrayList<Int32>()
    let lock = Mutex()

    public init() {}

    public func register(chord: Chord, id: Int32, action: Action): Bool {
        let ok = unsafe { RegisterHotKey(NULL_HWND, id, chord.registerModifiers(), chord.vk) }
        if (ok) {
            synchronized(this.lock) {
                this.ids.add(id)
            }
        }
        return ok
    }

    public func unregisterAll(): Unit {
        var copy = ArrayList<Int32>()
        synchronized(this.lock) {
            copy = ArrayList<Int32>(this.ids)
            this.ids.clear()
        }
        for (id in copy) {
            unsafe { UnregisterHotKey(NULL_HWND, id) }
        }
    }

    public func registeredCount(): Int64 {
        var c: Int64 = 0
        synchronized(this.lock) {
            c = this.ids.size
        }
        return c
    }
}