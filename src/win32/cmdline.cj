package winun.win32

import std.collection.*
import winun.infra.*

// 读取以 NUL 结尾的 UTF-16 指针（借道 WideCharToMultiByte 转成 UTF-8）
public func readUtf16Pointer(p: CPointer<UInt16>): String {
    if (p.isNull()) {
        return ""
    }
    var buf = Array<UInt8>(8192, repeat: 0)
    let handle = unsafe { acquireArrayRawData(buf) }
    let n = unsafe {
        WideCharToMultiByte(65001, 0, p, -1, handle.pointer, 8192, CPointer<UInt8>(), CPointer<Unit>())
    }
    unsafe { releaseArrayRawData(handle) }
    if (n <= 1) {
        return ""
    }
    var out = Array<UInt8>(Int64(n - 1), repeat: 0)
    for (i in 0..(Int64(n) - 1)) {
        out[i] = buf[i]
    }
    return String.fromUtf8(out)
}

// 按 Windows 命令行规则拆分（支持双引号包裹、反斜杠转义引号）
public func splitWindowsCommandLine(line: String): ArrayList<String> {
    let out = ArrayList<String>()
    var cur = ArrayList<UInt8>()
    var inQuotes = false
    var started = false
    let bytes = line.toArray()
    var i: Int64 = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == 0x22) { // '"'
            if (inQuotes && i + 1 < bytes.size && bytes[i + 1] == 0x22) {
                cur.add(0x22)
                i = i + 2
                continue
            }
            inQuotes = !inQuotes
            started = true
            i = i + 1
            continue
        }
        if (!inQuotes && (b == 0x20 || b == 0x09)) {
            if (started || cur.size > 0) {
                out.add(String.fromUtf8(cur.toArray()))
                cur = ArrayList<UInt8>()
                started = false
            }
            i = i + 1
            continue
        }
        cur.add(b)
        started = true
        i = i + 1
    }
    if (started || cur.size > 0) {
        out.add(String.fromUtf8(cur.toArray()))
    }
    return out
}

// 进程启动参数：绕开仓颉运行时的 args 传递
public func commandLineArgs(): Array<String> {
    let line = readUtf16Pointer(unsafe { GetCommandLineW() })
    return splitWindowsCommandLine(line).toArray()
}
