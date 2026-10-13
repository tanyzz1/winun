package winun.domain

import std.unittest.*
import std.unittest.testmacro.*

@Test
func testChordParsing() {
    let (c, err) = parseChord("win+alt+1")
    var ok = false
    match (c) {
        case Some(ch) =>
            ok = err.isEmpty() && ch.vk == 0x31 && (ch.modifiers & MOD_WIN) != 0 && (ch.modifiers & MOD_ALT) != 0
        case None => ok = false
    }
    @Assert(ok)
}

@Test
func testChordRejectsInvalidInput() {
    var a = false
    match (parseChord("a")[0]) {
        case None => a = true
        case _ => ()
    }
    var b = false
    match (parseChord("win+nosuchkey")[0]) {
        case None => b = true
        case _ => ()
    }
    var c = false
    match (parseChord("ctrl+win+tab")[0]) {
        case Some(_) => c = true
        case _ => ()
    }
    @Assert(a && b && c)
}

@Test
func testActionParsing() {
    var ok = true
    match (parseAction("launch dev-env")[0]) {
        case Some(Action.Launch(id)) => ok = ok && id == "dev-env"
        case _ => ok = false
    }
    match (parseAction("group cycle next")[0]) {
        case Some(Action.GroupCycleNext) => ()
        case _ => ok = false
    }
    match (parseAction("window snap left-half")[0]) {
        case Some(Action.WindowSnap(t)) =>
            match (t) {
                case SnapTarget.LeftHalf => ()
                case _ => ok = false
            }
        case _ => ok = false
    }
    match (parseAction("window float toggle")[0]) {
        case Some(Action.WindowFloatToggle) => ()
        case _ => ok = false
    }
    match (parseAction("nonsense here")[0]) {
        case None => ()
        case _ => ok = false
    }
    @Assert(ok)
}

@Test
func testWildcardMatch() {
    @Assert(wildcardMatch("C:\\Apps\\*\\code.exe", "c:\\apps\\microsoft\\code.exe"))
    @Assert(!wildcardMatch("C:\\Apps\\*\\code.exe", "c:\\other\\code.exe"))
    @Assert(wildcardMatch("*.exe", "app.exe"))
    @Assert(!wildcardMatch("*.exe", "app.txt"))
}

@Test
func testMatchesApp() {
    let spec = AppSpec()
    spec.matchExe = "Code.exe"
    spec.matchTitle = ".*Visual Studio Code"
    let info = WindowInfo()
    info.exeName = "code.exe"
    info.exePath = "C:\\Apps\\Code.exe"
    info.title = "main.cj - Visual Studio Code"
    @Assert(matchesApp(info, spec))
    info.title = "记事本"
    @Assert(!matchesApp(info, spec))
}
