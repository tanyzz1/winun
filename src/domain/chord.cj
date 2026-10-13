package winun.domain

import std.collection.*

// Win32 常量
public let MOD_ALT: UInt32 = 0x0001
public let MOD_CONTROL: UInt32 = 0x0002
public let MOD_SHIFT: UInt32 = 0x0004
public let MOD_WIN: UInt32 = 0x0008
public let MOD_NOREPEAT: UInt32 = 0x4000

public struct Chord {
    public var modifiers: UInt32 = 0
    public var vk: UInt32 = 0
    public var text: String = ""

    public init(modifiers!: UInt32 = 0, vk!: UInt32 = 0, text!: String = "") {
        this.modifiers = modifiers
        this.vk = vk
        this.text = text
    }

    // 注册用的修饰键（附带 MOD_NOREPEAT，避免长按重复触发）
    public func registerModifiers(): UInt32 {
        return this.modifiers | MOD_NOREPEAT
    }
}

let KEY_TABLE: HashMap<String, UInt32> = buildKeyTable()

func buildKeyTable(): HashMap<String, UInt32> {
    let m = HashMap<String, UInt32>()
    // 字母
    for (c in 0..26) {
        m.add(String.fromUtf8([UInt8(97 + c)]), UInt32(0x41 + c))
    }
    // 数字
    for (c in 0..10) {
        m.add(String.fromUtf8([UInt8(48 + c)]), UInt32(0x30 + c))
    }
    // 功能键
    for (c in 0..24) {
        m.add("f" + (c + 1).toString(), UInt32(0x70 + c))
    }
    m.add("left", 0x25)
    m.add("up", 0x26)
    m.add("right", 0x27)
    m.add("down", 0x28)
    m.add("home", 0x24)
    m.add("end", 0x23)
    m.add("pgup", 0x21)
    m.add("pgdn", 0x22)
    m.add("insert", 0x2D)
    m.add("delete", 0x2E)
    m.add("enter", 0x0D)
    m.add("esc", 0x1B)
    m.add("tab", 0x09)
    m.add("space", 0x20)
    m.add("backspace", 0x08)
    // OEM 符号键（物理键位）
    m.add("-", 0xBD)
    m.add("=", 0xBB)
    m.add("[", 0xDB)
    m.add("]", 0xDD)
    m.add(";", 0xBA)
    m.add("'", 0xDE)
    m.add(",", 0xBC)
    m.add(".", 0xBE)
    m.add("/", 0xBF)
    m.add("\\", 0xDC)
    m.add("`", 0xC0)
    return m
}

public func keyNameList(): Array<String> {
    let out = ArrayList<String>()
    for ((k, _) in KEY_TABLE) {
        out.add(k)
    }
    return out.toArray()
}

// 解析 "win+alt+1"；返回 (结果, 错误信息)
public func parseChord(text: String): (Option<Chord>, String) {
    let raw = text.trimAscii()
    if (raw.isEmpty()) {
        return (None, "组合键为空")
    }
    let parts = raw.split("+")
    if (parts.size < 2) {
        return (None, "组合键至少需要一个修饰键和一个主键，例如 win+alt+1")
    }
    var mods: UInt32 = 0
    var mainKey = ""
    var index: Int64 = 0
    for (p in parts) {
        let item = p.trimAscii().toAsciiLower()
        if (item.isEmpty()) {
            return (None, "组合键中出现空的片段")
        }
        if (index == parts.size - 1) {
            mainKey = item
        } else {
            match (item) {
                case "win" | "super" | "meta" => mods = mods | MOD_WIN
                case "ctrl" | "control" => mods = mods | MOD_CONTROL
                case "alt" => mods = mods | MOD_ALT
                case "shift" => mods = mods | MOD_SHIFT
                case _ => return (None, "未知的修饰键 '" + item + "'")
            }
        }
        index = index + 1
    }
    if (mods == 0) {
        return (None, "至少需要一个修饰键（win/ctrl/alt/shift）")
    }
    if (mainKey == "win" || mainKey == "ctrl" || mainKey == "alt" || mainKey == "shift") {
        return (None, "修饰键不能作为主键")
    }
    match (KEY_TABLE.get(mainKey)) {
        case Some(vk) => (Some(Chord(modifiers: mods, vk: vk, text: normalizeChord(mods, mainKey))), "")
        case None => (None, "未知的按键 '" + mainKey + "'")
    }
}

func normalizeChord(mods: UInt32, key: String): String {
    var s = ""
    if ((mods & MOD_WIN) != 0) { s = s + "win+" }
    if ((mods & MOD_CONTROL) != 0) { s = s + "ctrl+" }
    if ((mods & MOD_ALT) != 0) { s = s + "alt+" }
    if ((mods & MOD_SHIFT) != 0) { s = s + "shift+" }
    return s + key
}
