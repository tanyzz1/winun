package winun.infra

import std.collection.*
import std.env.*

// ---------- UTF-8 <-> UTF-16 转换（Windows W 系列 API 必需） ----------

public func utf16Encode(s: String): Array<UInt16> {
    let bytes = s.toArray()
    let out = ArrayList<UInt16>()
    var i: Int64 = 0
    while (i < bytes.size) {
        let b0 = bytes[i]
        var cp: UInt32 = 0
        var len: Int64 = 1
        if (b0 < 0x80) {
            cp = UInt32(b0)
            len = 1
        } else if ((b0 & 0xE0) == 0xC0) {
            cp = UInt32(b0 & 0x1F)
            len = 2
        } else if ((b0 & 0xF0) == 0xE0) {
            cp = UInt32(b0 & 0x0F)
            len = 3
        } else {
            cp = UInt32(b0 & 0x07)
            len = 4
        }
        var k: Int64 = 1
        while (k < len && i + k < bytes.size) {
            cp = (cp << 6) | UInt32(bytes[i + k] & 0x3F)
            k = k + 1
        }
        i = i + len
        if (cp >= 0x10000) {
            let v = cp - 0x10000
            out.add(UInt16(0xD800 + (v >> 10)))
            out.add(UInt16(0xDC00 + (v & 0x3FF)))
        } else {
            out.add(UInt16(cp))
        }
    }
    return out.toArray()
}

public func utf16Decode(units: Array<UInt16>, count: Int64): String {
    let out = ArrayList<UInt8>()
    var i: Int64 = 0
    while (i < count && i < units.size) {
        let u = units[i]
        var cp: UInt32 = UInt32(u)
        if (u >= 0xD800 && u <= 0xDBFF) {
            // 高代理：只有在紧跟合法低代理时才组成增补平面字符
            if (i + 1 < count && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF) {
                let lo = units[i + 1]
                cp = UInt32(0x10000) + ((UInt32(u) - 0xD800) << 10) + (UInt32(lo) - 0xDC00)
                i = i + 1
            } else {
                // 孤立的高代理：直接编码会产生非法 UTF-8，替换为 U+FFFD
                cp = 0xFFFD
            }
        } else if (u >= 0xDC00 && u <= 0xDFFF) {
            // 孤立的低代理：同样替换，避免窗口标题里的脏数据把程序打崩
            cp = 0xFFFD
        }
        appendUtf8Bytes(out, cp)
        i = i + 1
    }
    return String.fromUtf8(out.toArray())
}

// UTF-8 安全截断：按字节上限截取，但不切断多字节字符（否则会构造出非法 UTF-8 字符串）
public func truncateUtf8(s: String, maxBytes: Int64): String {
    let bytes = s.toArray()
    if (bytes.size <= maxBytes) {
        return s
    }
    var end = maxBytes
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
        end = end - 1
    }
    var out = Array<UInt8>(end, repeat: 0)
    for (i in 0..end) {
        out[i] = bytes[i]
    }
    return String.fromUtf8(out)
}

// ---------- 环境变量展开：%VAR% 与 ${env:VAR} ----------

public func expandEnv(s: String): String {
    let out = ArrayList<UInt8>()
    let bytes = s.toArray()
    var i: Int64 = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b == 0x25) { // '%'
            let end = indexOfByte(bytes, 0x25, i + 1)
            if (end > i + 1) {
                let name = sliceString(bytes, i + 1, end)
                match (getVariable(name)) {
                    case Some(v) => appendBytes(out, v)
                    case None => appendRange(out, bytes, i, end + 1)
                }
                i = end + 1
                continue
            }
        }
        if (b == 0x24 && i + 6 < bytes.size && bytes[i + 1] == 0x7B) { // '${'
            let end = indexOfByte(bytes, 0x7D, i + 2)
            if (end > i) {
                let inner = sliceString(bytes, i + 2, end)
                if (inner.startsWith("env:")) {
                    let name = inner[4..inner.size]
                    match (getVariable(name)) {
                        case Some(v) => appendBytes(out, v)
                        case None => appendRange(out, bytes, i, end + 1)
                    }
                    i = end + 1
                    continue
                }
            }
        }
        out.add(b)
        i = i + 1
    }
    return String.fromUtf8(out.toArray())
}

// 逐字节追加可能把多字节字符切断，因此统一按整串字节追加
func appendBytes(out: ArrayList<UInt8>, s: String): Unit {
    for (b in s.toArray()) {
        out.add(b)
    }
}

func appendRange(out: ArrayList<UInt8>, src: Array<UInt8>, from: Int64, to: Int64): Unit {
    var i = from
    while (i < to && i < src.size) {
        out.add(src[i])
        i = i + 1
    }
}

func indexOfByte(bytes: Array<UInt8>, target: UInt8, from: Int64): Int64 {
    var i = from
    while (i < bytes.size) {
        if (bytes[i] == target) {
            return i
        }
        i = i + 1
    }
    return -1
}

func sliceString(bytes: Array<UInt8>, from: Int64, to: Int64): String {
    if (to <= from) {
        return ""
    }
    var out = Array<UInt8>(to - from, repeat: 0)
    for (i in from..to) {
        out[i - from] = bytes[i]
    }
    return String.fromUtf8(out)
}

public func fileNameOf(path: String): String {
    var last: Int64 = -1
    let bytes = path.toArray()
    for (i in 0..bytes.size) {
        if (bytes[i] == 0x5C || bytes[i] == 0x2F) {
            last = i
        }
    }
    if (last < 0) {
        return path
    }
    return sliceString(bytes, last + 1, bytes.size)
}

public func parentDirOf(path: String): String {
    var last: Int64 = -1
    let bytes = path.toArray()
    for (i in 0..bytes.size) {
        if (bytes[i] == 0x5C || bytes[i] == 0x2F) {
            last = i
        }
    }
    if (last <= 0) {
        return ""
    }
    return sliceString(bytes, 0, last)
}

public func stripExtension(name: String): String {
    let bytes = name.toArray()
    var i = bytes.size - 1
    while (i >= 0) {
        if (bytes[i] == 0x2E) {
            return sliceString(bytes, 0, i)
        }
        i = i - 1
    }
    return name
}

public func equalsIgnoreCase(a: String, b: String): Bool {
    return a.toAsciiLower() == b.toAsciiLower()
}