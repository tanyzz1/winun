package winun.config

import std.unittest.*
import std.unittest.testmacro.*

let MINIMAL = """
{
  "version": 1,
  "hotkeys": {"win+alt+1": "launch dev-env"},
  "apps": {"vscode": {"exe": "code.exe", "match": {"exe": "Code.exe"}}},
  "launches": {"dev-env": {"apps": ["vscode"], "group": "coding"}},
  "layouts": {"two-columns": {"type": "grid", "columns": 2, "rows": 1}},
  "groups": {"coding": {"layout": "two-columns", "apps": ["vscode"], "onSwitchAway": "minimize"}}
}
"""

@Test
func testMinimalConfigIsValid() {
    let r = parseConfig(MINIMAL, "<test>")
    @Assert(r.ok())
    @Expect(r.snapshot.apps.size, 1)
    @Expect(r.snapshot.groups.size, 1)
    @Expect(r.snapshot.hotkeys.size, 1)
    @Expect(r.snapshot.launchOrder[0], "dev-env")
}

@Test
func testDanglingReferencesAreErrors() {
    let text = """
{
  "version": 1,
  "apps": {"vscode": {"exe": "code.exe"}},
  "launches": {"dev": {"apps": ["missing-app"], "group": "missing-group"}},
  "groups": {"coding": {"layout": "missing-layout", "apps": ["vscode"]}}
}
"""
    let r = parseConfig(text, "<test>")
    @Assert(!r.ok())
    var hasAppError = false
    var hasGroupError = false
    var hasLayoutError = false
    for (e in r.errors) {
        if (e.contains("missing-app")) { hasAppError = true }
        if (e.contains("missing-group")) { hasGroupError = true }
        if (e.contains("missing-layout")) { hasLayoutError = true }
    }
    @Assert(hasAppError && hasGroupError && hasLayoutError)
}

@Test
func testBadHotkeyAndAction() {
    let text = """
{
  "version": 1,
  "hotkeys": {"ctrl+a": "nonsense action", "win+alt+": "quit"}
}
"""
    let r = parseConfig(text, "<test>")
    @Assert(!r.ok())
    @Assert(r.errors.size >= 2)
}

@Test
func testSyntaxErrorCarriesPosition() {
    let r = parseConfig("""
{
  "version": 1,
  "apps": {,
}
""", "winun.json")
    @Assert(!r.ok())
    @Assert(r.errors[0].contains("winun.json:3") || r.errors[0].contains("E1001"))
}

@Test
func testTypeMismatchIsReported() {
    let text = """
{
  "version": 1,
  "behavior": {"watchConfig": "yes"},
  "log": {"level": "verbose"}
}
"""
    let r = parseConfig(text, "<test>")
    @Assert(!r.ok())
    var hasWatch = false
    var hasLevel = false
    for (e in r.errors) {
        if (e.contains("watchConfig")) { hasWatch = true }
        if (e.contains("log.level")) { hasLevel = true }
    }
    @Assert(hasWatch && hasLevel)
}

@Test
func testUnknownKeyIsWarningByDefault() {
    let text = """
{
  "version": 1,
  "typo": 1
}
"""
    let r = parseConfig(text, "<test>")
    @Assert(r.ok())
    @Assert(r.warnings.size >= 1)
}

@Test
func testUnknownKeyIsErrorInStrictMode() {
    let text = """
{
  "version": 1,
  "behavior": {"strict": true},
  "typo": 1
}
"""
    let r = parseConfig(text, "<test>")
    @Assert(!r.ok())
}
