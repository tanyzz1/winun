package winun.win32

import winun.domain.*
import winun.infra.*

// 自建窗口所需的最小窗口类支持：用于 winun selftest 的自窗口集成测试
@C
public struct WNDCLASSEXW {
    public var cbSize: UInt32 = 0
    public var style: UInt32 = 0
    public var lpfnWndProc: CFunc<(HWND, UInt32, UInt64, Int64) -> Int64> = DefWindowProcW
    public var cbClsExtra: Int32 = 0
    public var cbWndExtra: Int32 = 0
    public var hInstance: CPointer<Unit> = CPointer<Unit>()
    public var hIcon: CPointer<Unit> = CPointer<Unit>()
    public var hCursor: CPointer<Unit> = CPointer<Unit>()
    public var hbrBackground: CPointer<Unit> = CPointer<Unit>()
    public var lpszMenuName: CPointer<UInt16> = CPointer<UInt16>()
    public var lpszClassName: CPointer<UInt16> = CPointer<UInt16>()
    public var hIconSm: CPointer<Unit> = CPointer<Unit>()
}

@CallingConv[STDCALL]
foreign func GetModuleHandleW(name: CPointer<UInt16>): CPointer<Unit>
@CallingConv[STDCALL]
foreign func RegisterClassExW(wc: CPointer<WNDCLASSEXW>): UInt16
@CallingConv[STDCALL]
foreign func CreateWindowExW(exStyle: UInt32, cls: CPointer<UInt16>, title: CPointer<UInt16>, style: UInt32,
    x: Int32, y: Int32, w: Int32, h: Int32, parent: HWND, menu: CPointer<Unit>,
    inst: CPointer<Unit>, param: CPointer<Unit>): HWND
@CallingConv[STDCALL]
foreign func DefWindowProcW(hwnd: HWND, msg: UInt32, wParam: UInt64, lParam: Int64): Int64
@CallingConv[STDCALL]
foreign func DestroyWindow(hwnd: HWND): Bool
@CallingConv[STDCALL]
foreign func PeekMessageW(msg: CPointer<MSG>, hwnd: HWND, min: UInt32, max: UInt32, remove: UInt32): Bool

public let WS_OVERLAPPEDWINDOW: UInt32 = 0x00CF0000

let PROBE_CLASS = "WinunSelfTestWindow"
var gClassRegistered = false

// 创建隐藏的探针窗口（不显示，避免打扰用户；位置仍可被 SetWindowPos 修改并读回）
public func createProbeWindow(title: String, x: Int32, y: Int32, w: Int32, h: Int32): HWND {
    let inst = unsafe { GetModuleHandleW(CPointer<UInt16>()) }
    let clsUnits = utf16Encode(PROBE_CLASS)
    let clsHandle = unsafe { acquireArrayRawData(clsUnits) }
    if (!gClassRegistered) {
        var wc = WNDCLASSEXW()
        wc.cbSize = UInt32(sizeOf<WNDCLASSEXW>())
        wc.hInstance = inst
        wc.lpszClassName = clsHandle.pointer
        let atom = unsafe { RegisterClassExW(inout wc) }
        // atom == 0 时多半是类已存在（ERROR_CLASS_ALREADY_EXISTS），仍然可以创建窗口
        let _ = atom
        gClassRegistered = true
    }
    let titleUnits = utf16Encode(title)
    let titleHandle = unsafe { acquireArrayRawData(titleUnits) }
    let hwnd = unsafe {
        CreateWindowExW(UInt32(WS_EX_TOOLWINDOW), clsHandle.pointer, titleHandle.pointer, WS_OVERLAPPEDWINDOW,
            x, y, w, h, HWND(), CPointer<Unit>(), inst, CPointer<Unit>())
    }
    unsafe { releaseArrayRawData(titleHandle) }
    unsafe { releaseArrayRawData(clsHandle) }
    return hwnd
}

public func destroyProbeWindow(hwnd: HWND): Unit {
    if (!hwnd.isNull()) {
        unsafe { DestroyWindow(hwnd) }
    }
}

public func windowRectOf(hwnd: HWND): Rect {
    var r = RECTC()
    let ok = unsafe { GetWindowRect(hwnd, inout r) }
    if (!ok) {
        return Rect()
    }
    return Rect(left: r.left, top: r.top, right: r.right, bottom: r.bottom)
}

// 确保当前线程有消息队列（RegisterHotKey 之前的常规动作）
public func ensureMessageQueue(): Bool {
    var msg = MSG()
    return unsafe { PeekMessageW(inout msg, HWND(), 0, 0, 0) }
}
