package spike

public type HWND = CPointer<Unit>
@CallingConv[STDCALL]
foreign func PostThreadMessageW(threadId: UInt32, msg: UInt32, wParam: UInt64, lParam: Int64): Bool
foreign func Sleep(ms: UInt32): Unit

// 模拟操作系统在热键按下时投递的 WM_HOTKEY（id=1 对应 win+alt+f1，id=2 对应 win+alt+z）
main() {
    let target: UInt32 = 284076
    let ok1 = unsafe { PostThreadMessageW(target, 0x0312, 1, 0) }
    println("投递 WM_HOTKEY id=1 (win+alt+f1 -> config reload) => " + ok1.toString())
    unsafe { Sleep(800) }
    let ok2 = unsafe { PostThreadMessageW(target, 0x0312, 2, 0) }
    println("投递 WM_HOTKEY id=2 (win+alt+z -> quit) => " + ok2.toString())
    unsafe { Sleep(500) }
}
