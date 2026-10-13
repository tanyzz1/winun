package winun.win32

// Win32 FFI 声明：只声明 winun 需要的部分，全部集中在 winun.win32 包内
public type HANDLE = CPointer<Unit>
public type LPVOID = CPointer<Unit>

public let WM_HOTKEY: UInt32 = 0x0312
public let WM_APP: UInt32 = 0x8000
public let WM_QUIT: UInt32 = 0x0012

public let SWP_NOZORDER: UInt32 = 0x0004
public let SWP_NOACTIVATE: UInt32 = 0x0010
public let SWP_SHOWWINDOW: UInt32 = 0x0040
public let SWP_FRAMECHANGED: UInt32 = 0x0020

public let SW_HIDE: Int32 = 0
public let SW_SHOWNORMAL: Int32 = 1
public let SW_SHOWNOACTIVATE: Int32 = 4
public let SW_SHOW: Int32 = 5
public let SW_MINIMIZE: Int32 = 6
public let SW_RESTORE: Int32 = 9
public let SW_SHOWMAXIMIZED: Int32 = 3

public let GWL_STYLE: Int32 = -16
public let GWL_EXSTYLE: Int32 = -20
public let WS_EX_TOOLWINDOW: Int64 = 0x00000080
public let WS_EX_APPWINDOW: Int64 = 0x00040000
public let WS_CHILD: Int64 = 0x40000000

public let PROCESS_QUERY_LIMITED_INFORMATION: UInt32 = 0x1000
public let MONITOR_DEFAULTTONEAREST: UInt32 = 2
public let DWMWA_EXTENDED_FRAME_BOUNDS: UInt32 = 9
public let ERROR_ALREADY_EXISTS: UInt32 = 183
public let ERROR_HOTKEY_ALREADY_REGISTERED: UInt32 = 1409
public let CREATE_UNICODE_ENVIRONMENT: UInt32 = 0x00000400
public let STARTF_USESHOWWINDOW: UInt32 = 0x00000001

@C
public struct POINT {
    public var x: Int32 = 0
    public var y: Int32 = 0
}

@C
public struct RECTC {
    public var left: Int32 = 0
    public var top: Int32 = 0
    public var right: Int32 = 0
    public var bottom: Int32 = 0
}

@C
public struct MSG {
    public var hwnd: HWND = NULL_HWND
    public var message: UInt32 = 0
    public var wParam: UInt64 = 0
    public var lParam: Int64 = 0
    public var time: UInt32 = 0
    public var pt: POINT = POINT()
}

@C
public struct MONITORINFO {
    public var cbSize: UInt32 = 0
    public var rcMonitor: RECTC = RECTC()
    public var rcWork: RECTC = RECTC()
    public var dwFlags: UInt32 = 0
}

@C
public struct STARTUPINFOW {
    public var cb: UInt32 = 0
    public var lpReserved: CPointer<UInt16> = CPointer<UInt16>()
    public var lpDesktop: CPointer<UInt16> = CPointer<UInt16>()
    public var lpTitle: CPointer<UInt16> = CPointer<UInt16>()
    public var dwX: UInt32 = 0
    public var dwY: UInt32 = 0
    public var dwXSize: UInt32 = 0
    public var dwYSize: UInt32 = 0
    public var dwXCountChars: UInt32 = 0
    public var dwYCountChars: UInt32 = 0
    public var dwFillAttribute: UInt32 = 0
    public var dwFlags: UInt32 = 0
    public var wShowWindow: UInt16 = 0
    public var cbReserved2: UInt16 = 0
    public var lpReserved2: CPointer<UInt8> = CPointer<UInt8>()
    public var hStdInput: HANDLE = HANDLE()
    public var hStdOutput: HANDLE = HANDLE()
    public var hStdError: HANDLE = HANDLE()
}

@C
public struct PROCESS_INFORMATION {
    public var hProcess: HANDLE = HANDLE()
    public var hThread: HANDLE = HANDLE()
    public var dwProcessId: UInt32 = 0
    public var dwThreadId: UInt32 = 0
}

// ---------- 热键与消息 ----------
@CallingConv[STDCALL]
foreign func RegisterHotKey(hWnd: HWND, id: Int32, fsModifiers: UInt32, vk: UInt32): Bool
@CallingConv[STDCALL]
foreign func UnregisterHotKey(hWnd: HWND, id: Int32): Bool
@CallingConv[STDCALL]
foreign func GetMessageW(lpMsg: CPointer<MSG>, hWnd: HWND, min: UInt32, max: UInt32): Int32
@CallingConv[STDCALL]
foreign func TranslateMessage(lpMsg: CPointer<MSG>): Bool
@CallingConv[STDCALL]
foreign func DispatchMessageW(lpMsg: CPointer<MSG>): Int64
@CallingConv[STDCALL]
foreign func PostQuitMessage(code: Int32): Unit
@CallingConv[STDCALL]
foreign func PostThreadMessageW(threadId: UInt32, msg: UInt32, wParam: UInt64, lParam: Int64): Bool
foreign func GetCurrentThreadId(): UInt32
foreign func Sleep(ms: UInt32): Unit

// ---------- 窗口枚举与信息 ----------
@CallingConv[STDCALL]
foreign func EnumWindows(cb: CFunc<(HWND, Int64) -> Bool>, lParam: Int64): Bool
@CallingConv[STDCALL]
foreign func IsWindow(hWnd: HWND): Bool
@CallingConv[STDCALL]
foreign func IsWindowVisible(hWnd: HWND): Bool
@CallingConv[STDCALL]
foreign func IsIconic(hWnd: HWND): Bool
@CallingConv[STDCALL]
foreign func IsZoomed(hWnd: HWND): Bool
@CallingConv[STDCALL]
foreign func GetWindowTextW(hWnd: HWND, buf: CPointer<UInt16>, max: Int32): Int32
@CallingConv[STDCALL]
foreign func GetWindowTextLengthW(hWnd: HWND): Int32
@CallingConv[STDCALL]
foreign func GetClassNameW(hWnd: HWND, buf: CPointer<UInt16>, max: Int32): Int32
@CallingConv[STDCALL]
foreign func GetWindowRect(hWnd: HWND, lpRect: CPointer<RECTC>): Bool
@CallingConv[STDCALL]
foreign func GetWindowLongPtrW(hWnd: HWND, index: Int32): Int64
@CallingConv[STDCALL]
foreign func GetForegroundWindow(): HWND
@CallingConv[STDCALL]
foreign func GetWindowThreadProcessId(hWnd: HWND, pid: CPointer<UInt32>): UInt32

// ---------- 窗口操作 ----------
@CallingConv[STDCALL]
foreign func SetWindowPos(hWnd: HWND, after: HWND, x: Int32, y: Int32, cx: Int32, cy: Int32, flags: UInt32): Bool
@CallingConv[STDCALL]
foreign func ShowWindow(hWnd: HWND, cmd: Int32): Bool
@CallingConv[STDCALL]
foreign func SetForegroundWindow(hWnd: HWND): Bool
@CallingConv[STDCALL]
foreign func AllowSetForegroundWindow(pid: UInt32): Bool
@CallingConv[STDCALL]
foreign func BringWindowToTop(hWnd: HWND): Bool

// ---------- 显示器 / DWM ----------
@CallingConv[STDCALL]
foreign func MonitorFromWindow(hWnd: HWND, flags: UInt32): HANDLE
@CallingConv[STDCALL]
foreign func GetMonitorInfoW(monitor: HANDLE, info: CPointer<MONITORINFO>): Bool
@CallingConv[STDCALL]
foreign func GetSystemMetrics(index: Int32): Int32
@CallingConv[STDCALL]
foreign func DwmGetWindowAttribute(hWnd: HWND, attr: UInt32, value: CPointer<Unit>, size: UInt32): Int32

// ---------- 进程 ----------
@CallingConv[STDCALL]
foreign func OpenProcess(access: UInt32, inherit: Bool, pid: UInt32): HANDLE
@CallingConv[STDCALL]
foreign func CloseHandle(h: HANDLE): Bool
@CallingConv[STDCALL]
foreign func QueryFullProcessImageNameW(process: HANDLE, flags: UInt32, buf: CPointer<UInt16>, size: CPointer<UInt32>): Bool
@CallingConv[STDCALL]
foreign func CreateProcessW(appName: CPointer<UInt16>, cmdLine: CPointer<UInt16>,
    procAttr: CPointer<Unit>, threadAttr: CPointer<Unit>, inheritHandles: Bool, flags: UInt32,
    env: CPointer<Unit>, cwd: CPointer<UInt16>, startup: CPointer<STARTUPINFOW>,
    info: CPointer<PROCESS_INFORMATION>): Bool
@CallingConv[STDCALL]
foreign func WaitForInputIdle(process: HANDLE, ms: UInt32): UInt32

// ---------- 单实例与错误 ----------
@CallingConv[STDCALL]
foreign func CreateMutexW(attr: CPointer<Unit>, owner: Bool, name: CPointer<UInt16>): HANDLE
foreign func GetLastError(): UInt32
foreign func GetTickCount64(): UInt64

// 命令行：不走仓颉运行时的 args（本机环境下访问 main(args) 会挂起，见 docs/spike-report.md）
@CallingConv[STDCALL]
foreign func GetCommandLineW(): CPointer<UInt16>
@CallingConv[STDCALL]
foreign func WideCharToMultiByte(codePage: UInt32, flags: UInt32, src: CPointer<UInt16>,
    srcLen: Int32, dst: CPointer<UInt8>, dstLen: Int32, defChar: CPointer<UInt8>,
    usedDefault: CPointer<Unit>): Int32
