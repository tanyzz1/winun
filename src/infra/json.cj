package winun.infra

import std.collection.*
import std.convert.*

public enum JsonValue {
    | JNull
    | JBool(Bool)
    | JInt(Int64)
    | JNum(Float64)
    | JStr(String)
    | JArr(ArrayList<JsonValue>)
    | JObj(HashMap<String, JsonValue>)
}

// ---------- 访问器 ----------

public func jsonAsObject(v: JsonValue): Option<HashMap<String, JsonValue>> {
    match (v) {
        case JObj(m) => Some(m)
        case _ => None
    }
}

public func jsonAsArray(v: JsonValue): Option<ArrayList<JsonValue>> {
    match (v) {
        case JArr(a) => Some(a)
        case _ => None
    }
}

public func jsonAsString(v: JsonValue): Option<String> {
    match (v) {
        case JStr(s) => Some(s)
        case _ => None
    }
}

public func jsonAsBool(v: JsonValue): Option<Bool> {
    match (v) {
        case JBool(b) => Some(b)
        case _ => None
    }
}

public func jsonAsInt(v: JsonValue): Option<Int64> {
    match (v) {
        case JInt(i) => Some(i)
        case _ => None
    }
}

public func jsonAsNumber(v: JsonValue): Option<Float64> {
    match (v) {
        case JInt(i) => Some(Float64(i))
        case JNum(f) => Some(f)
        case _ => None
    }
}

public func jsonTypeName(v: JsonValue): String {
    match (v) {
        case JNull => "null"
        case JBool(_) => "boolean"
        case JInt(_) => "integer"
        case JNum(_) => "number"
        case JStr(_) => "string"
        case JArr(_) => "array"
        case JObj(_) => "object"
    }
}

// ---------- 解析器（递归下降，带行列号） ----------

class JsonParser {
    let src: Array<UInt8>
    var pos: Int64 = 0
    var line: Int64 = 1
    var col: Int64 = 1

    init(text: String) {
        this.src = text.toArray()
    }

    func fail(msg: String): Nothing {
        throw JsonError(msg, this.line, this.col)
    }

    func eof(): Bool {
        return this.pos >= this.src.size
    }

    func peek(): UInt8 {
        if (this.eof()) {
            return 0
        }
        return this.src[this.pos]
    }

    func advance(): UInt8 {
        let b = this.src[this.pos]
        this.pos = this.pos + 1
        if (b == 0x0A) {
            this.line = this.line + 1
            this.col = 1
        } else if (b >= 0x80) {
            // UTF-8 续字节不占列宽，简单按字节计数即可
            this.col = this.col + 1
        } else {
            this.col = this.col + 1
        }
        return b
    }

    func skipWs() {
        while (!this.eof()) {
            let b = this.peek()
            if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) {
                this.advance()
            } else {
                break
            }
        }
    }

    func expect(b: UInt8, what: String) {
        if (this.eof() || this.peek() != b) {
            this.fail("期望 '" + String.fromUtf8([b]) + "'（" + what + "）")
        }
        this.advance()
    }

    func parseValue(): JsonValue {
        this.skipWs()
        if (this.eof()) {
            this.fail("意外的输入结束，期望一个 JSON 值")
        }
        let b = this.peek()
        if (b == 0x7B) {
            return this.parseObject()
        }
        if (b == 0x5B) {
            return this.parseArray()
        }
        if (b == 0x22) {
            return JStr(this.parseString())
        }
        if (b == 0x74) {
            this.parseLiteral("true")
            return JBool(true)
        }
        if (b == 0x66) {
            this.parseLiteral("false")
            return JBool(false)
        }
        if (b == 0x6E) {
            this.parseLiteral("null")
            return JNull
        }
        if (b == 0x2D || (b >= 0x30 && b <= 0x39)) {
            return this.parseNumber()
        }
        this.fail("非法字符 '" + String.fromUtf8([b]) + "'")
    }

    func parseLiteral(word: String) {
        for (w in word.toArray()) {
            if (this.eof() || this.peek() != w) {
                this.fail("非法字面量，期望 '" + word + "'")
            }
            this.advance()
        }
    }

    func parseObject(): JsonValue {
        this.expect(0x7B, "对象开始")
        let m = HashMap<String, JsonValue>()
        this.skipWs()
        if (!this.eof() && this.peek() == 0x7D) {
            this.advance()
            return JObj(m)
        }
        while (true) {
            this.skipWs()
            if (this.eof() || this.peek() != 0x22) {
                this.fail("对象的键必须是字符串")
            }
            let key = this.parseString()
            this.skipWs()
            this.expect(0x3A, "键值分隔符 ':'")
            let value = this.parseValue()
            if (m.contains(key)) {
                this.fail("重复的键 '" + key + "'")
            }
            m.add(key, value)
            this.skipWs()
            if (this.eof()) {
                this.fail("对象未闭合，期望 '}'")
            }
            let b = this.peek()
            if (b == 0x2C) {
                this.advance()
                continue
            }
            if (b == 0x7D) {
                this.advance()
                return JObj(m)
            }
            this.fail("对象中出现非法字符，期望 ',' 或 '}'")
        }
        return JObj(m)
    }

    func parseArray(): JsonValue {
        this.expect(0x5B, "数组开始")
        let a = ArrayList<JsonValue>()
        this.skipWs()
        if (!this.eof() && this.peek() == 0x5D) {
            this.advance()
            return JArr(a)
        }
        while (true) {
            a.add(this.parseValue())
            this.skipWs()
            if (this.eof()) {
                this.fail("数组未闭合，期望 ']'")
            }
            let b = this.peek()
            if (b == 0x2C) {
                this.advance()
                continue
            }
            if (b == 0x5D) {
                this.advance()
                return JArr(a)
            }
            this.fail("数组中出现非法字符，期望 ',' 或 ']'")
        }
        return JArr(a)
    }

    func parseNumber(): JsonValue {
        var sb = ArrayList<UInt8>()
        if (this.peek() == 0x2D) {
            sb.add(this.advance())
        }
        var isFloat = false
        while (!this.eof()) {
            let b = this.peek()
            if (b >= 0x30 && b <= 0x39) {
                sb.add(this.advance())
            } else if (b == 0x2E || b == 0x65 || b == 0x45 || b == 0x2B || b == 0x2D) {
                if (b == 0x2E || b == 0x65 || b == 0x45) {
                    isFloat = true
                }
                sb.add(this.advance())
            } else {
                break
            }
        }
        let text = String.fromUtf8(sb.toArray())
        if (text == "-" || text.isEmpty()) {
            this.fail("非法的数字")
        }
        if (isFloat) {
            return JNum(Float64.parse(text))
        }
        return JInt(Int64.parse(text))
    }

    func parseString(): String {
        this.expect(0x22, "字符串开始")
        let out = ArrayList<UInt8>()
        while (true) {
            if (this.eof()) {
                this.fail("字符串未闭合")
            }
            let b = this.advance()
            if (b == 0x22) {
                return String.fromUtf8(out.toArray())
            }
            if (b == 0x5C) {
                if (this.eof()) {
                    this.fail("转义序列不完整")
                }
                let e = this.advance()
                match (e) {
                    case 0x22 => out.add(0x22)
                    case 0x5C => out.add(0x5C)
                    case 0x2F => out.add(0x2F)
                    case 0x62 => out.add(0x08)
                    case 0x66 => out.add(0x0C)
                    case 0x6E => out.add(0x0A)
                    case 0x72 => out.add(0x0D)
                    case 0x74 => out.add(0x09)
                    case 0x75 => this.appendUnicodeEscape(out)
                    case _ => this.fail("非法的转义字符")
                }
                continue
            }
            if (b < 0x20) {
                this.fail("字符串中出现未转义的控制字符")
            }
            out.add(b)
        }
        return ""
    }

    func appendUnicodeEscape(out: ArrayList<UInt8>) {
        var cp: UInt32 = 0
        for (_ in 0..4) {
            if (this.eof()) {
                this.fail("\\u 转义不完整")
            }
            let h = this.advance()
            let d: UInt32 = hexValue(h)
            cp = cp * 16 + d
        }
        appendUtf8Bytes(out, cp)
    }
}

func hexValue(b: UInt8): UInt32 {
    if (b >= 0x30 && b <= 0x39) {
        return UInt32(b - 0x30)
    }
    if (b >= 0x61 && b <= 0x66) {
        return UInt32(b - 0x61) + 10
    }
    if (b >= 0x41 && b <= 0x46) {
        return UInt32(b - 0x41) + 10
    }
    throw JsonError("非法的十六进制字符", 0, 0)
}

func appendUtf8Bytes(out: ArrayList<UInt8>, cp: UInt32) {
    if (cp < 0x80) {
        out.add(UInt8(cp))
    } else if (cp < 0x800) {
        out.add(UInt8(0xC0 | (cp >> 6)))
        out.add(UInt8(0x80 | (cp & 0x3F)))
    } else if (cp < 0x10000) {
        out.add(UInt8(0xE0 | (cp >> 12)))
        out.add(UInt8(0x80 | ((cp >> 6) & 0x3F)))
        out.add(UInt8(0x80 | (cp & 0x3F)))
    } else {
        out.add(UInt8(0xF0 | (cp >> 18)))
        out.add(UInt8(0x80 | ((cp >> 12) & 0x3F)))
        out.add(UInt8(0x80 | ((cp >> 6) & 0x3F)))
        out.add(UInt8(0x80 | (cp & 0x3F)))
    }
}

public func parseJson(text: String): JsonValue {
    let p = JsonParser(stripBom(text))
    let v = p.parseValue()
    p.skipWs()
    if (!p.eof()) {
        p.fail("JSON 文档结束后存在多余内容")
    }
    return v
}

func stripBom(text: String): String {
    let bytes = text.toArray()
    if (bytes.size >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        var rest = Array<UInt8>(bytes.size - 3, repeat: 0)
        for (i in 3..bytes.size) {
            rest[i - 3] = bytes[i]
        }
        return String.fromUtf8(rest)
    }
    return text
}

// ---------- 序列化（用于 list --json 等诊断输出） ----------

public func toJsonText(v: JsonValue, indent: Int64): String {
    return renderJson(v, indent, 0)
}

func pad(n: Int64): String {
    var s = ""
    for (_ in 0..n) {
        s = s + " "
    }
    return s
}

func escapeJson(s: String): String {
    var out = "\""
    for (b in s.toArray()) {
        match (b) {
            case 0x22 => out = out + "\\\""
            case 0x5C => out = out + "\\\\"
            case 0x0A => out = out + "\\n"
            case 0x0D => out = out + "\\r"
            case 0x09 => out = out + "\\t"
            case _ => out = out + String.fromUtf8([b])
        }
    }
    return out + "\""
}

func renderJson(v: JsonValue, indent: Int64, depth: Int64): String {
    match (v) {
        case JNull => "null"
        case JBool(b) => if (b) { "true" } else { "false" }
        case JInt(i) => i.toString()
        case JNum(f) => f.toString()
        case JStr(s) => escapeJson(s)
        case JArr(a) =>
            if (a.size == 0) {
                "[]"
            } else {
                var s = "["
                for (i in 0..a.size) {
                    if (i > 0) { s = s + "," }
                    if (indent > 0) { s = s + "\n" + pad((depth + 1) * indent) }
                    s = s + renderJson(a[i], indent, depth + 1)
                }
                if (indent > 0) { s = s + "\n" + pad(depth * indent) }
                s + "]"
            }
        case JObj(m) =>
            if (m.size == 0) {
                "{}"
            } else {
                var s = "{"
                var first = true
                for ((k, val) in m) {
                    if (!first) { s = s + "," }
                    first = false
                    if (indent > 0) { s = s + "\n" + pad((depth + 1) * indent) }
                    s = s + escapeJson(k) + ":" + (if (indent > 0) { " " } else { "" }) + renderJson(val, indent, depth + 1)
                }
                if (indent > 0) { s = s + "\n" + pad(depth * indent) }
                s + "}"
            }
    }
}
