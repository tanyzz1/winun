package winun.core

import std.unittest.*
import std.unittest.testmacro.*
import winun.config.*
import winun.domain.*
import winun.infra.*
import winun.platform.*

let CFG_TEXT = """
{
  "version": 1,
  "apps": {
    "editor":  {"exe": "editor.exe",  "match": {"exe": "editor.exe"}},
    "term":    {"exe": "term.exe",    "match": {"exe": "term.exe"}},
    "browser": {"exe": "browser.exe", "match": {"exe": "browser.exe"}}
  },
  "launches": {
    "dev-env": {"apps": ["editor", "term"], "group": "coding", "staggerMs": 0}
  },
  "layouts": {
    "two-columns": {"type": "grid", "columns": 2, "rows": 1, "gap": 0, "margins": [0, 0, 0, 0]},
    "half": {"type": "anchor", "anchor": "left", "size": ["50%", "100%"]}
  },
  "groups": {
    "coding":  {"layout": "two-columns", "apps": ["editor", "term"], "onSwitchAway": "minimize", "activate": "focus-first"},
    "browser": {"layout": "half", "apps": ["browser"], "onSwitchAway": "hide", "activate": "focus-first"}
  }
}
"""

class Fixture {
    var dispatcher: Dispatcher
    var backend: RecordingWindowBackend
    var launcher: RecordingLauncher
    var hotkeys: RecordingHotkeys
    var clock: FakeClock

    init() {
        let r = parseConfig(CFG_TEXT, "<test>")
        this.backend = RecordingWindowBackend()
        this.backend.area = Rect(left: 0, top: 0, right: 1000, bottom: 600)
        this.launcher = RecordingLauncher()
        this.launcher.backend = Some(this.backend)
        this.launcher.register("editor", "editor.exe")
        this.launcher.register("term", "term.exe")
        this.launcher.register("browser", "browser.exe")
        this.hotkeys = RecordingHotkeys()
        this.clock = FakeClock()
        let log = Logger(LogLevel.Error, "", false)
        this.dispatcher = Dispatcher(this.backend, this.launcher, this.hotkeys, this.clock, r.snapshot, log)
    }
}

@Test
func testLaunchSetLaunchesAdoptsAndLaysOut() {
    let f = Fixture()
    f.dispatcher.dispatch(Action.Launch("dev-env"))

    @Expect(f.launcher.launched.size, 2)
    @Expect(f.launcher.launched[0], "editor")
    @Expect(f.launcher.launched[1], "term")
    @Expect(f.dispatcher.session.activeGroup, "coding")
    @Expect(f.backend.placed.size, 2)
    // two-columns: 0..500 / 500..1000
    @Expect(f.backend.placed[0].rect.left, 0)
    @Expect(f.backend.placed[0].rect.right, 500)
    @Expect(f.backend.placed[1].rect.left, 500)
    @Expect(f.backend.placed[1].rect.right, 1000)
    @Expect(f.dispatcher.registry.membersOf("coding").size, 2)
}

@Test
func testGroupSwitchAppliesSwitchAwayPolicy() {
    let f = Fixture()
    f.dispatcher.dispatch(Action.Launch("dev-env"))
    f.backend.clearCalls()

    // browser 组里先放一个窗口
    let browserWindow = f.backend.addWindow("browser.exe", "browser")
    f.dispatcher.registry.refresh(f.backend, f.dispatcher.cfg)
    f.dispatcher.registry.adopt("browser", browserWindow)

    f.dispatcher.dispatch(Action.GroupActivate("browser"))

    // 旧组（coding）按 onSwitchAway = minimize 处理
    @Expect(f.backend.minimized.size, 2)
    // 新组按 half 布局（1000 宽的一半）
    @Expect(f.backend.placed.size, 1)
    @Expect(f.backend.placed[0].rect.left, 0)
    @Expect(f.backend.placed[0].rect.right, 500)
    @Expect(f.dispatcher.session.activeGroup, "browser")
}

@Test
func testGroupCycleWrapsAround() {
    let f = Fixture()
    f.dispatcher.dispatch(Action.GroupActivate("coding"))
    f.dispatcher.dispatch(Action.GroupCycleNext)
    @Expect(f.dispatcher.session.activeGroup, "browser")
    f.dispatcher.dispatch(Action.GroupCycleNext)
    @Expect(f.dispatcher.session.activeGroup, "coding")
    f.dispatcher.dispatch(Action.GroupCyclePrev)
    @Expect(f.dispatcher.session.activeGroup, "browser")
}

@Test
func testSnapForegroundWindow() {
    let f = Fixture()
    let id = f.backend.addWindow("editor.exe", "scratch")
    f.backend.foreground = id
    f.dispatcher.dispatch(Action.WindowSnap(SnapTarget.LeftHalf))
    @Expect(f.backend.placed.size, 1)
    @Expect(f.backend.placed[0].rect.left, 0)
    @Expect(f.backend.placed[0].rect.right, 500)
    @Expect(f.backend.placed[0].rect.bottom, 600)
}

@Test
func testWindowToGroupCurrent() {
    let f = Fixture()
    f.dispatcher.dispatch(Action.Launch("dev-env"))
    let extra = f.backend.addWindow("browser.exe", "extra")
    f.backend.foreground = extra
    f.dispatcher.dispatch(Action.WindowToGroup("current"))
    // 新窗口被收编进当前组（coding）
    @Expect(f.dispatcher.registry.membersOf("coding").size, 3)
    // 并触发一次重新布局
    @Expect(f.backend.placed.size >= 3, true)
}

@Test
func testReloadAndQuitFlags() {
    let f = Fixture()
    f.dispatcher.dispatch(Action.ConfigReload)
    @Assert(f.dispatcher.reloadRequested)
    f.dispatcher.dispatch(Action.Quit)
    @Assert(f.dispatcher.shouldQuit)
}
