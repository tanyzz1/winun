package winun.infra

import std.unittest.*
import std.unittest.testmacro.*

@Test
func testJsonParseBasics() {
    let v = parseJson("""
{"n": 42, "s": "中", "b": true, "arr": [1, 2]}
""")
    var ok = false
    match (v) {
        case JObj(m) =>
            ok = m.size == 4
            match (m["n"]) {
                case JInt(i) => ok = ok && i == 42
                case _ => ok = false
            }
            match (m["s"]) {
                case JStr(s) => ok = ok && s == "中"
                case _ => ok = false
            }
            match (m["b"]) {
                case JBool(b) => ok = ok && b
                case _ => ok = false
            }
            match (m["arr"]) {
                case JArr(a) => ok = ok && a.size == 2
                case _ => ok = false
            }
        case _ => ok = false
    }
    @Assert(ok)
}

@Test
func testJsonRejectsDuplicateKey() {
    var caught = false
    try {
        let _ = parseJson("""
{"a": 1, "a": 2}
""")
    } catch (e: JsonError) {
        caught = true
    }
    @Assert(caught)
}

@Test
func testJsonSyntaxErrorReportsLine() {
    var line: Int64 = 0
    var caught = false
    try {
        let _ = parseJson("""
{
  "a": ,
}
""")
    } catch (e: JsonError) {
        line = e.line
        caught = true
    }
    @Assert(caught)
    @Assert(line >= 2 && line <= 5)
}

@Test
func testJsonRoundTrip() {
    let text = """
{"a": [1, 2, 3], "b": {"c": "d"}, "e": null, "f": false}
"""
    let v = parseJson(text)
    let out = toJsonText(v, 0)
    let v2 = parseJson(out)
    @Expect(toJsonText(v2, 0), out)
}

@Test
func testJsonEscapes() {
    // 用字节构造 JSON，避免测试代码自身卷入多层转义：JSON 里的 \\ 应当解码成一个反斜杠
    let q = String.fromUtf8([0x22])
    let bs = String.fromUtf8([0x5C])
    let text = "{" + q + "p" + q + ": " + q + "C:" + bs + bs + "dir" + q + "}"
    let v = parseJson(text)
    var ok = false
    match (v) {
        case JObj(m) =>
            match (m.get("p")) {
                case Some(JStr(s)) => ok = s == "C:" + bs + "dir"
                case _ => ok = false
            }
        case _ => ok = false
    }
    @Assert(ok)
}

@Test
func testUtf16RoundTrip() {
    let s = "winun 中文 😀 test"
    let u = utf16Encode(s)
    @Expect(utf16Decode(u, u.size), s)
}

@Test
func testExpandEnvKeepsUnknownVariable() {
    @Expect(expandEnv("%NO_SUCH_VAR_XYZ%\\a"), "%NO_SUCH_VAR_XYZ%\\a")
}

@Test
func testTruncateUtf8KeepsBoundary() {
    let s = "中文abc"
    @Expect(truncateUtf8(s, 3), "中")
    @Expect(truncateUtf8(s, 4), "中")
    @Expect(truncateUtf8(s, 6), "中文")
    @Expect(truncateUtf8(s, 100), s)
}

@Test
func testUtf16DecodeHandlesLoneSurrogate() {
    // 窗口标题里可能出现落单的代理项：必须替换为 U+FFFD，而不是构造非法 UTF-8 抛异常
    let units: Array<UInt16> = [0xD800, 0x41]
    let s = utf16Decode(units, units.size)
    @Assert(s.endsWith("A"))
    let units2: Array<UInt16> = [0xDC00, 0x42]
    let s2 = utf16Decode(units2, units2.size)
    @Assert(s2.endsWith("B"))
}

@Test
func testExpandEnvPreservesMultiByte() {
    @Expect(expandEnv("前缀%NO_SUCH_VAR%后缀"), "前缀%NO_SUCH_VAR%后缀")
}

@Test
func testFileNameHelpers() {
    @Expect(fileNameOf("C:\\Program Files\\App\\app.exe"), "app.exe")
    @Expect(stripExtension("app.exe"), "app")
    @Assert(equalsIgnoreCase("Code.EXE", "code.exe"))
}