package winun.win32

import std.collection.*
import std.sync.*
import winun.domain.*

public type HWND = CPointer<Unit>

public let NULL_HWND: HWND = HWND()

// 仓颉的 CPointer 只能单向转整数（toUIntNative），因此维护一张 id -> HWND 表
let gHandleLock = Mutex()
let gHandles = HashMap<Int64, HWND>()

public func registerHandle(p: HWND): WindowId {
    if (p.isNull()) {
        return WindowId()
    }
    let raw = Int64(p.toUIntNative())
    synchronized(gHandleLock) {
        if (gHandles.contains(raw)) {
            gHandles[raw] = p
        } else {
            gHandles.add(raw, p)
        }
    }
    return WindowId(value: raw)
}

public func toHwnd(id: WindowId): HWND {
    if (id.isNull()) {
        return NULL_HWND
    }
    var found = NULL_HWND
    synchronized(gHandleLock) {
        match (gHandles.get(id.value)) {
            case Some(h) => found = h
            case None => found = NULL_HWND
        }
    }
    return found
}
