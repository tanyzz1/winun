package winun.cli

import std.collection.*
import std.env.*
import winun.app.*
import winun.config.*
import winun.core.*
import winun.domain.*
import winun.infra.*
import winun.layout.*
import winun.platform.*
import winun.win32.*

public let WINUN_VERSION = "0.1.0"
public let WINUN_CONFIG_NAME = "winun.json"

public class CliOptions {
    var command: String = "run"
    var configPath: String = ""
    var consoleOut: Bool = false
    var dryRun: Bool = false
    var asJson: Bool = false
    var positional: ArrayList<String> = ArrayList<String>()

    init() {}
}

public func runCli(args: Array<String>): Int64 {
    let opts = parseArgs(args)
    match (opts.command) {
        case "version" =>
            printVersion()
            return 0
        case "help" =>
            printHelp()
            return 0
        case "validate" =>
            return validateCommand(opts)
        case "list" =>
            return listCommand(opts)
        case "run" =>
            return runCommand(opts)
        case "smoke" =>
            return smokeCommand()
        case "selftest" =>
            return selfTestCommand(opts)
        case _ =>
            println("未知命令：" + opts.command)
            printHelp()
            return 1
    }
}

func printVersion(): Unit {
    println("winun " + WINUN_VERSION + " (仓颉 / cjnative, Windows x64)")
}

func printHelp(): Unit {
    println("winun " + WINUN_VERSION + " - 配置驱动的 Windows 窗口管理器")
    println("")
    println("用法：winun [命令] [选项]")
    println("")
    println("命令：")
    println("  run                  常驻运行，注册热键并等待（默认命令）")
    println("  validate             只校验配置文件并输出诊断")
    println("  list <目标>          列出 windows|groups|layouts|apps|launches|hotkeys")
    println("  selftest             平台自检：ABI 断言 + 自窗口布局闭环（沙箱内也可运行）")
    println("  version              打印版本")
    println("  help                 打印本帮助")
    println("")
    println("选项：")
    println("  -c, --config <路径>  指定配置文件（默认 %APPDATA%\\winun\\winun.json，回退到 config\\winun.json）")
    println("      --console        日志同时输出到控制台")
    println("      --dry-run        只打印将要执行的动作，不真正操作窗口")
    println("      --json           以 JSON 输出 list 结果")
}

func parseArgs(args: Array<String>): CliOptions {
    let o = CliOptions()
    var i: Int64 = 1
    while (i < args.size) {
        let a = args[i]
        match (a) {
            case "--config" | "-c" =>
                if (i + 1 < args.size) {
                    o.configPath = args[i + 1]
                    i = i + 2
                    continue
                }
            case "--console" => o.consoleOut = true
            case "--dry-run" => o.dryRun = true
            case "--json" => o.asJson = true
            case "--help" | "-h" => o.command = "help"
            case _ =>
                if (!a.startsWith("-")) {
                    if (o.command == "run" && o.positional.size == 0 && isKnownCommand(a)) {
                        o.command = a
                    } else {
                        o.positional.add(a)
                    }
                }
        }
        i = i + 1
    }
    return o
}

func isKnownCommand(s: String): Bool {
    match (s) {
        case "run" | "validate" | "list" | "version" | "help" | "smoke" | "selftest" => true
        case _ => false
    }
}

func resolveConfigPath(explicit: String): String {
    if (!explicit.isEmpty()) {
        return explicit
    }
    match (getVariable("APPDATA")) {
        case Some(v) =>
            let p = v + "\\winun\\" + WINUN_CONFIG_NAME
            if (fileExists(p)) {
                return p
            }
        case None => ()
    }
    let local = "config\\" + WINUN_CONFIG_NAME
    if (fileExists(local)) {
        return local
    }
    return local
}

// ---------- validate ----------

func validateCommand(o: CliOptions): Int64 {
    let path = resolveConfigPath(o.configPath)
    println("校验配置文件：" + path)
    let r = loadConfigFile(path)
    for (w in r.warnings) {
        println("[警告] " + w)
    }
    for (e in r.errors) {
        println("[错误] " + e)
    }
    if (r.ok()) {
        println("配置有效：" + r.snapshot.summary())
        return 0
    }
    println("配置无效：" + r.errors.size.toString() + " 个错误，" + r.warnings.size.toString() + " 个警告")
    return 2
}

// ---------- list ----------

func listCommand(o: CliOptions): Int64 {
    let path = resolveConfigPath(o.configPath)
    let r = loadConfigFile(path)
    if (!r.ok()) {
        for (e in r.errors) {
            println("[错误] " + e)
        }
        return 2
    }
    let snap = r.snapshot
    let what = if (o.positional.size > 0) { o.positional[0] } else { "summary" }
    match (what) {
        case "windows" => listWindows(snap)
        case "groups" =>
            println("组（按声明顺序）：")
            for (id in snap.groupOrder) {
                println("  " + snap.groups[id].describe())
            }
        case "layouts" =>
            println("布局：")
            for (id in snap.layoutOrder) {
                println("  " + snap.layouts[id].describe())
            }
        case "apps" =>
            println("应用：")
            for (id in snap.appOrder) {
                println("  " + snap.apps[id].describe())
            }
        case "launches" =>
            println("启动集合：")
            for (id in snap.launchOrder) {
                println("  " + snap.launches[id].describe())
            }
        case "hotkeys" =>
            println("热键：")
            for (b in snap.hotkeys) {
                println("  " + b.describe())
            }
        case _ =>
            println("配置摘要：" + snap.summary())
            println("  组：" + joinStrings(snap.groupOrder))
            println("  布局：" + joinStrings(snap.layoutOrder))
            println("  应用：" + joinStrings(snap.appOrder))
            println("  启动集合：" + joinStrings(snap.launchOrder))
    }
    return 0
}

func joinStrings(items: ArrayList<String>): String {
    var s = ""
    for (i in 0..items.size) {
        if (i > 0) {
            s = s + ", "
        }
        s = s + items[i]
    }
    return s
}

func listWindows(snap: ConfigSnapshot): Unit {
    let backend = Win32WindowBackend()
    let windows = backend.listWindows()
    println("候选窗口（" + windows.size.toString() + " 个，已过滤不可见/工具窗口）：")
    println("  HWND                 PID     进程                 类名                             标题                          匹配应用")
    var matched: Int64 = 0
    for (w in windows) {
        var app = "-"
        for (id in snap.appOrder) {
            if (matchesApp(w, snap.apps[id])) {
                app = id
                break
            }
        }
        if (app != "-") {
            matched = matched + 1
        }
        println("  " + padTo(w.id.describe(), 20) + padTo(w.pid.toString(), 9) +
            padTo(w.exeName, 21) + padTo(w.className, 33) + padTo(truncate(w.title, 28), 30) + app)
    }
    println("其中 " + matched.toString() + " 个窗口匹配到配置中的应用（这些窗口会被收编与布局）")
}

func padTo(s: String, width: Int64): String {
    var out = s
    while (out.size < width) {
        out = out + " "
    }
    return out + " "
}

func truncate(s: String, max: Int64): String {
    // 标题里常有中文/emoji，按字节硬切会构造出非法 UTF-8，必须按字符边界截断
    return truncateUtf8(s, max)
}

// ---------- run ----------

func runCommand(o: CliOptions): Int64 {
    let path = resolveConfigPath(o.configPath)
    let r = loadConfigFile(path)
    for (w in r.warnings) {
        println("[警告] " + w)
    }
    if (!r.ok()) {
        for (e in r.errors) {
            println("[错误] " + e)
        }
        println("配置无效，已退出")
        return 2
    }
    let snap = r.snapshot
    let log = Logger(snap.logLevel, snap.logFile, o.consoleOut)
    log.info("cli", "配置文件：" + path + "（" + snap.summary() + "）")

    if (!acquireSingleInstance("winun-single-instance-v1")) {
        log.error("cli", "已有 winun 实例在运行，退出")
        return 5
    }

    let host = Host(snap, log)
    let count = host.warmUp()
    log.info("cli", "已识别 " + count.toString() + " 个可见窗口")

    if (o.dryRun) {
        log.info("cli", "--dry-run：只打印将要注册的热键")
        for (b in snap.hotkeys) {
            log.info("cli", "  热键 " + b.chordText + " -> " + b.actionText)
        }
        return 0
    }

    let registered = host.registerHotkeys()
    log.info("cli", "热键注册结果：" + registered.toString() + "/" + snap.hotkeys.size.toString() + " 成功")
    if (registered == 0 && snap.hotkeys.size > 0) {
        log.warn("cli", "没有任何热键注册成功（可能全部被占用，或当前环境不允许注册全局热键）")
    }
    host.startGroup()
    return host.run()
}

// ---------- selftest：平台写路径自检 ----------

func selfTestCommand(o: CliOptions): Int64 {
    println("winun 平台自检（只使用本进程自建的隐藏窗口，不依赖其它进程）")
    let results = runSelfTest()
    var failed = 0
    var skipped = 0
    for (r in results) {
        let detail = if (r.detail.isEmpty()) { "" } else { "  — " + r.detail }
        println("  [" + statusName(r.status) + "] " + r.name + detail)
        match (r.status) {
            case CheckStatus.Failed => failed = failed + 1
            case CheckStatus.Skipped => skipped = skipped + 1
            case CheckStatus.Passed => ()
        }
    }
    println("结果：" + results.size.toString() + " 项，失败 " + failed.toString() + " 项，跳过 " + skipped.toString() + " 项")

    // 配置里的热键逐条探测：区分"本机已被占用"与"环境不允许"
    let path = resolveConfigPath(o.configPath)
    if (fileExists(path)) {
        let r = loadConfigFile(path)
        if (r.ok() && r.snapshot.hotkeys.size > 0) {
            println("")
            println("配置热键占用探测（" + path + "）：")
            let probe = Win32Hotkeys()
            var id: Int32 = 1
            var taken = 0
            for (b in r.snapshot.hotkeys) {
                let ok = probe.register(b.chord, id, b.action)
                if (ok) {
                    probe.unregisterAll()
                } else {
                    taken = taken + 1
                }
                println("  [" + (if (ok) { "空闲" } else { "占用" }) + "] " + padTo(b.chordText, 18) + " -> " + b.actionText)
                id = id + 1
            }
            if (taken > 0) {
                println("提示：有 " + taken.toString() + " 个组合键不可用（已被其它程序占用，或 winun 正在运行）。")
                println("      改成本机空闲的组合键即可；实测 win+alt+f1..f12 通常是空闲的。")
            } else {
                println("全部组合键均可用。")
            }
        }
    }
    if (failed > 0) {
        println("提示：窗口写路径若整体失败，说明运行环境限制了窗口操作；请参考 docs/M1-实施记录.md 第 4.7 节")
        return 4
    }
    return 0
}

// ---------- smoke：自检纯逻辑链路 ----------

func smokeCommand(): Int64 {
    println("winun 自检")
    let text = """
{"version": 1, "hotkeys": {"win+alt+1": "launch dev-env"}, "apps": {"vscode": {"exe": "code.exe"}}, "launches": {"dev-env": {"apps": ["vscode"]}}, "layouts": {"two-columns": {"type": "grid", "columns": 2, "rows": 1}}, "groups": {"coding": {"layout": "two-columns", "apps": ["vscode"]}}}
"""
    let r = parseConfig(text, "<smoke>")
    println("  配置解析：" + (if (r.ok()) { "通过" } else { "失败" }) + " " + r.snapshot.summary())
    for (e in r.errors) {
        println("  [错误] " + e)
    }
    let spec = LayoutSpec()
    spec.kind = LayoutKind.Grid
    spec.columns = 2
    spec.rows = 1
    spec.gap = 8
    let placements = solve([WindowId(value: 1), WindowId(value: 2)], spec, Rect(left: 0, top: 0, right: 1000, bottom: 500))
    println("  布局解算：")
    print(describePlacements(placements))
    let (chord, err) = parseChord("win+alt+1")
    match (chord) {
        case Some(c) => println("  组合键：" + c.text + " mods=0x" + c.modifiers.toString() + " vk=0x" + c.vk.toString())
        case None => println("  组合键解析失败：" + err)
    }
    let u = utf16Encode("winun 中文 😀")
    println("  UTF-16 往返：" + utf16Decode(u, u.size))
    return 0
}