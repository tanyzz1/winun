package winun.win32

import winun.infra.*
import winun.platform.*

// 消息循环对外的安全封装：foreign 声明本身是包内可见，这里提供公开入口
//
// 注意：MSG 是结构体，按值传参不会把 GetMessageW 写入的内容带回调用者，
// 因此必须用结果对象把 MSG 带回去（这正是"热键无反应"的根因）。
public class PumpedMessage {
    public var result: Int32 = 0
    public var msg: MSG = MSG()

    public init() {}

    public func isHotkey(): Bool {
        return this.msg.message == WM_HOTKEY
    }

    public func hotkeyId(): Int32 {
        return Int32(this.msg.wParam & 0xFFFF)
    }
}

public func pumpMessage(): PumpedMessage {
    let out = PumpedMessage()
    var m = MSG()
    out.result = unsafe { GetMessageW(inout m, NULL_HWND, 0, 0) }
    out.msg = m
    return out
}

public func translateMessage(msg: MSG): Bool {
    var m = msg
    return unsafe { TranslateMessage(inout m) }
}

public func dispatchMessage(msg: MSG): Int64 {
    var m = msg
    return unsafe { DispatchMessageW(inout m) }
}

// 队列里是否有消息（不阻塞、不移除）
public func hasAnyMessage(): Bool {
    var m = MSG()
    return unsafe { PeekMessageW(inout m, NULL_HWND, 0, 0, 0) }
}

// 自投递一个 WM_HOTKEY 到指定线程：用于在不按键的情况下验证热键消息闭环
public func postThreadHotkey(threadId: UInt32, id: Int32): Bool {
    return unsafe { PostThreadMessageW(threadId, WM_HOTKEY, UInt64(UInt32(id)), 0) }
}

public func postQuit(): Unit {
    unsafe { PostQuitMessage(0) }
}

public func currentThreadId(): UInt32 {
    return unsafe { GetCurrentThreadId() }
}

public func sleepMs(ms: Int64): Unit {
    unsafe { Sleep(UInt32(ms)) }
}

// 单实例：命名互斥体
public func acquireSingleInstance(name: String): Bool {
    let units = utf16Encode(name)
    let handle = unsafe { acquireArrayRawData(units) }
    let h = unsafe { CreateMutexW(CPointer<Unit>(), false, handle.pointer) }
    unsafe { releaseArrayRawData(handle) }
    if (h.isNull()) {
        return false
    }
    let err = unsafe { GetLastError() }
    if (err == ERROR_ALREADY_EXISTS) {
        return false
    }
    return true
}

public class Win32Clock <: Clock {
    public init() {}
    public func nowMs(): Int64 { return Int64(unsafe { GetTickCount64() }) }
    public func sleepMs(ms: Int64): Unit { unsafe { Sleep(UInt32(ms)) } }
}
