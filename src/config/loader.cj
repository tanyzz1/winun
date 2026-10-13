package winun.config

import std.collection.*
import std.convert.*
import std.fs.*
import std.regex.*
import winun.domain.*
import winun.infra.*

// ---------- 读取与解析入口 ----------

public func loadConfigFile(path: String): LoadResult {
    var text = ""
    try {
        let bytes = File.readFrom(path)
        text = String.fromUtf8(bytes)
    } catch (e: Exception) {
        let r = LoadResult()
        r.snapshot.sourcePath = path
        r.errors.add("E1000 " + path + ": 无法读取配置文件（" + e.message + "）")
        return r
    }
    return parseConfig(text, path)
}

public func parseConfig(text: String, sourcePath: String): LoadResult {
    let result = LoadResult()
    result.snapshot.sourcePath = sourcePath
    var root: JsonValue = JNull
    try {
        root = parseJson(text)
    } catch (e: JsonError) {
        result.errors.add("E1001 " + sourcePath + ":" + e.line.toString() + ":" + e.column.toString() + ": JSON 语法错误：" + e.message)
        return result
    }
    match (root) {
        case JObj(top) => parseTop(top, result)
        case _ => result.errors.add("E1002 " + sourcePath + ": 顶层必须是一个 JSON 对象")
    }
    return result
}

// ---------- 顶层 ----------

let TOP_KEYS = ["\$schema", "\$comment", "version", "log", "behavior", "hotkeys", "apps", "launches", "layouts", "groups"]

func parseTop(top: HashMap<String, JsonValue>, result: LoadResult) {
    match (top.get("version")) {
        case Some(JInt(v)) =>
            if (v != 1) {
                result.errors.add("E2001 version: 当前仅支持配置版本 1，实际为 " + v.toString())
            }
        case Some(_) => result.errors.add("E2002 version: 必须是整数")
        case None => ()
    }
    match (top.get("log")) {
        case Some(JObj(m)) => parseLog(m, result)
        case Some(_) => result.errors.add("E2002 log: 必须是对象")
        case None => ()
    }
    match (top.get("behavior")) {
        case Some(JObj(m)) => parseBehavior(m, result)
        case Some(_) => result.errors.add("E2002 behavior: 必须是对象")
        case None => ()
    }
    match (top.get("apps")) {
        case Some(JObj(m)) => parseApps(m, result)
        case Some(_) => result.errors.add("E2002 apps: 必须是对象")
        case None => ()
    }
    match (top.get("layouts")) {
        case Some(JObj(m)) => parseLayouts(m, result)
        case Some(_) => result.errors.add("E2002 layouts: 必须是对象")
        case None => ()
    }
    match (top.get("groups")) {
        case Some(JObj(m)) => parseGroups(m, result)
        case Some(_) => result.errors.add("E2002 groups: 必须是对象")
        case None => ()
    }
    match (top.get("launches")) {
        case Some(JObj(m)) => parseLaunches(m, result)
        case Some(_) => result.errors.add("E2002 launches: 必须是对象")
        case None => ()
    }
    match (top.get("hotkeys")) {
        case Some(JObj(m)) => parseHotkeys(m, result)
        case Some(_) => result.errors.add("E2002 hotkeys: 必须是对象")
        case None => ()
    }
    // 未知键在最后统一处理：behavior.strict 会把警告升级为错误
    for ((k, _) in top) {
        // $ 前缀为约定保留（$schema / $comment 及自定义说明），静默忽略
        if (k.startsWith("$")) {
            continue
        }
        if (!containsString(TOP_KEYS, k)) {
            report(result, "E2000", k, "未知的顶层键（已忽略）")
        }
    }
    crossCheck(result)
}

func parseLog(m: HashMap<String, JsonValue>, result: LoadResult) {
    match (m.get("level")) {
        case Some(JStr(s)) =>
            match (parseLogLevel(s)) {
                case Some(l) => result.snapshot.logLevel = l
                case None => result.errors.add("E2003 log.level: 取值必须是 debug/info/warn/error，实际为 \"" + s + "\"")
            }
        case Some(_) => result.errors.add("E2002 log.level: 必须是字符串")
        case None => ()
    }
    match (m.get("file")) {
        case Some(JStr(s)) => result.snapshot.logFile = expandEnv(s)
        case Some(_) => result.errors.add("E2002 log.file: 必须是字符串")
        case None => ()
    }
    match (m.get("rotateKb")) {
        case Some(JInt(v)) => result.snapshot.logRotateKb = v
        case Some(_) => result.errors.add("E2002 log.rotateKb: 必须是整数")
        case None => ()
    }
}

func parseBehavior(m: HashMap<String, JsonValue>, result: LoadResult) {
    match (m.get("watchConfig")) {
        case Some(JBool(b)) => result.snapshot.watchConfig = b
        case Some(_) => result.errors.add("E2002 behavior.watchConfig: 必须是布尔值")
        case None => ()
    }
    match (m.get("strict")) {
        case Some(JBool(b)) => result.snapshot.strict = b
        case Some(_) => result.errors.add("E2002 behavior.strict: 必须是布尔值")
        case None => ()
    }
    match (m.get("startupGroup")) {
        case Some(JStr(s)) => result.snapshot.startupGroup = s
        case Some(_) => result.errors.add("E2002 behavior.startupGroup: 必须是字符串")
        case None => ()
    }
    match (m.get("defaultLayout")) {
        case Some(JStr(s)) => result.snapshot.defaultLayout = s
        case Some(_) => result.errors.add("E2002 behavior.defaultLayout: 必须是字符串")
        case None => ()
    }
    match (m.get("commandTimeoutMs")) {
        case Some(JInt(v)) => result.snapshot.commandTimeoutMs = v
        case Some(_) => result.errors.add("E2002 behavior.commandTimeoutMs: 必须是整数")
        case None => ()
    }
}

// ---------- 动作与热键 ----------

func parseHotkeys(m: HashMap<String, JsonValue>, result: LoadResult) {
    let seen = HashMap<String, String>()
    for ((key, value) in m) {
        match (value) {
            case JStr(actionText) =>
                let (chordOpt, chordErr) = parseChord(key)
                if (!chordErr.isEmpty()) {
                    result.errors.add("E2004 hotkeys.\"" + key + "\": 非法组合键：" + chordErr)
                    continue
                }
                let (actionOpt, actionErr) = parseAction(actionText)
                if (!actionErr.isEmpty()) {
                    result.errors.add("E2005 hotkeys.\"" + key + "\": 非法动作：" + actionErr)
                    continue
                }
                let chord = match (chordOpt) {
                    case Some(c) => c
                    case None => Chord()
                }
                let action = match (actionOpt) {
                    case Some(a) => a
                    case None => Action.Quit
                }
                if (seen.contains(chord.text)) {
                    result.errors.add("E2006 hotkeys.\"" + key + "\": 与 \"" + (seen[chord.text]) + "\" 重复绑定同一个组合键")
                    continue
                }
                seen.add(chord.text, key)
                let binding = HotkeyBinding()
                binding.chordText = chord.text
                binding.chord = chord
                binding.action = action
                binding.actionText = actionText
                result.snapshot.hotkeys.add(binding)
            case _ => result.errors.add("E2002 hotkeys.\"" + key + "\": 值必须是动作字符串")
        }
    }
}

// ---------- 应用 ----------

func parseApps(m: HashMap<String, JsonValue>, result: LoadResult) {
    for ((id, value) in m) {
        let path = "apps." + id
        match (value) {
            case JObj(app) =>
                let spec = AppSpec()
                spec.id = id
                match (app.get("exe")) {
                    case Some(JStr(s)) => spec.exe = expandEnv(s)
                    case Some(_) => result.errors.add("E2002 " + path + ".exe: 必须是字符串")
                    case None => result.errors.add("E2003 " + path + ".exe: 缺少必填字段 exe")
                }
                spec.args = readStringArray(app, "args", path, result)
                match (app.get("cwd")) {
                    case Some(JStr(s)) => spec.cwd = expandEnv(s)
                    case Some(_) => result.errors.add("E2002 " + path + ".cwd: 必须是字符串")
                    case None => ()
                }
                match (app.get("env")) {
                    case Some(JObj(env)) =>
                        let pairs = ArrayList<(String, String)>()
                        for ((k, v) in env) {
                            match (v) {
                                case JStr(s) => pairs.add((k, expandEnv(s)))
                                case _ => result.errors.add("E2002 " + path + ".env." + k + ": 值必须是字符串")
                            }
                        }
                        spec.env = pairs.toArray()
                    case Some(_) => result.errors.add("E2002 " + path + ".env: 必须是对象")
                    case None => ()
                }
                match (app.get("match")) {
                    case Some(JObj(mm)) => parseMatch(mm, path, spec, result)
                    case Some(_) => result.errors.add("E2002 " + path + ".match: 必须是对象")
                    case None => ()
                }
                match (app.get("startupWaitMs")) {
                    case Some(JInt(v)) => spec.startupWaitMs = v
                    case Some(_) => result.errors.add("E2002 " + path + ".startupWaitMs: 必须是整数")
                    case None => ()
                }
                match (app.get("reuse")) {
                    case Some(JStr(s)) =>
                        let low = s.toAsciiLower()
                        if (low == "existing") {
                            spec.reuse = ReusePolicy.Existing
                        } else if (low == "new") {
                            spec.reuse = ReusePolicy.New
                        } else {
                            result.errors.add("E2003 " + path + ".reuse: 取值必须是 existing/new")
                        }
                    case Some(_) => result.errors.add("E2002 " + path + ".reuse: 必须是字符串")
                    case None => ()
                }
                match (app.get("maximizeOnStart")) {
                    case Some(JBool(b)) => spec.maximizeOnStart = b
                    case Some(_) => result.errors.add("E2002 " + path + ".maximizeOnStart: 必须是布尔值")
                    case None => ()
                }
                result.snapshot.apps.add(id, spec)
                result.snapshot.appOrder.add(id)
            case _ => result.errors.add("E2002 " + path + ": 必须是对象")
        }
    }
}

func parseMatch(m: HashMap<String, JsonValue>, path: String, spec: AppSpec, result: LoadResult) {
    for ((k, v) in m) {
        let key = path + ".match." + k
        match (v) {
            case JStr(s) =>
                match (k) {
                    case "exe" => spec.matchExe = s
                    case "path" => spec.matchPath = expandEnv(s)
                    case "class" => spec.matchClass = s
                    case "title" =>
                        try {
                            let _ = Regex(s)
                            spec.matchTitle = s
                        } catch (e: Exception) {
                            result.errors.add("E2006 " + key + ": 非法的正则表达式：" + e.message)
                        }
                    case _ => report(result, "E2000", key, "未知的匹配字段（已忽略）")
                }
            case _ => result.errors.add("E2002 " + key + ": 必须是字符串")
        }
    }
}

// ---------- 布局 ----------

func parseLayouts(m: HashMap<String, JsonValue>, result: LoadResult) {
    for ((id, value) in m) {
        let path = "layouts." + id
        match (value) {
            case JObj(o) =>
                let spec = LayoutSpec()
                spec.id = id
                match (o.get("type")) {
                    case Some(JStr(s)) =>
                        match (s.toAsciiLower()) {
                            case "grid" => spec.kind = LayoutKind.Grid
                            case "ratio" => spec.kind = LayoutKind.Ratio
                            case "absolute" => spec.kind = LayoutKind.Absolute
                            case "anchor" => spec.kind = LayoutKind.Anchor
                            case _ => result.errors.add("E2003 " + path + ".type: 取值必须是 grid/ratio/absolute/anchor")
                        }
                    case Some(_) => result.errors.add("E2002 " + path + ".type: 必须是字符串")
                    case None => result.errors.add("E2003 " + path + ".type: 缺少必填字段 type")
                }
                match (o.get("columns")) {
                    case Some(JInt(v)) => spec.columns = v
                    case Some(_) => result.errors.add("E2002 " + path + ".columns: 必须是整数")
                    case None => ()
                }
                match (o.get("rows")) {
                    case Some(JInt(v)) => spec.rows = v
                    case Some(_) => result.errors.add("E2002 " + path + ".rows: 必须是整数")
                    case None => ()
                }
                match (o.get("gap")) {
                    case Some(JInt(v)) => spec.gap = Int32(v)
                    case Some(_) => result.errors.add("E2002 " + path + ".gap: 必须是整数")
                    case None => ()
                }
                match (o.get("margins")) {
                    case Some(JArr(items)) => spec.margins = readMargins(items, path, result)
                    case Some(JInt(v)) => spec.margins = Margins(left: Int32(v), top: Int32(v), right: Int32(v), bottom: Int32(v))
                    case Some(_) => result.errors.add("E2002 " + path + ".margins: 必须是 4 个整数组成的数组")
                    case None => ()
                }
                match (o.get("ratios")) {
                    case Some(JArr(items)) =>
                        let ratios = ArrayList<Float64>()
                        for (it in items) {
                            match (jsonAsNumber(it)) {
                                case Some(f) => ratios.add(f)
                                case None => result.errors.add("E2002 " + path + ".ratios: 元素必须是数字")
                            }
                        }
                        spec.ratios = ratios.toArray()
                    case Some(_) => result.errors.add("E2002 " + path + ".ratios: 必须是数字数组")
                    case None => ()
                }
                match (o.get("cells")) {
                    case Some(JArr(items)) => spec.cells = readCells(items, path, result)
                    case Some(_) => result.errors.add("E2002 " + path + ".cells: 必须是数组")
                    case None => ()
                }
                match (o.get("monitor")) {
                    case Some(JStr(s)) => spec.monitor = readMonitorSelector(s, path, result)
                    case Some(JInt(v)) => spec.monitor = MonitorSelector.Index(v)
                    case Some(_) => result.errors.add("E2002 " + path + ".monitor: 必须是字符串或整数")
                    case None => ()
                }
                match (o.get("order")) {
                    case Some(JStr(s)) =>
                        match (s.toAsciiLower()) {
                            case "listed" => spec.order = OrderPolicy.Listed
                            case "zorder" => spec.order = OrderPolicy.ZOrder
                            case "title" => spec.order = OrderPolicy.Title
                            case _ => result.errors.add("E2003 " + path + ".order: 取值必须是 listed/zorder/title")
                        }
                    case Some(_) => result.errors.add("E2002 " + path + ".order: 必须是字符串")
                    case None => ()
                }
                match (o.get("anchor")) {
                    case Some(JStr(s)) => spec.anchor = readAnchor(s, path, result)
                    case Some(_) => result.errors.add("E2002 " + path + ".anchor: 必须是字符串")
                    case None => ()
                }
                match (o.get("size")) {
                    case Some(JArr(items)) => spec.sizePercent = readSize(items, path, result)
                    case Some(_) => result.errors.add("E2002 " + path + ".size: 必须是 [宽, 高] 数组")
                    case None => ()
                }
                result.snapshot.layouts.add(id, spec)
                result.snapshot.layoutOrder.add(id)
            case _ => result.errors.add("E2002 " + path + ": 必须是对象")
        }
    }
}

func readMargins(items: ArrayList<JsonValue>, path: String, result: LoadResult): Margins {
    if (items.size != 4) {
        result.errors.add("E2003 " + path + ".margins: 必须恰好 4 个整数")
        return Margins()
    }
    return Margins(left: readIntOr(items[0], path + ".margins", result),
        top: readIntOr(items[1], path + ".margins", result),
        right: readIntOr(items[2], path + ".margins", result),
        bottom: readIntOr(items[3], path + ".margins", result))
}

func readCells(items: ArrayList<JsonValue>, path: String, result: LoadResult): Array<Rect> {
    let out = ArrayList<Rect>()
    for (it in items) {
        match (it) {
            case JArr(cell) =>
                if (cell.size != 4) {
                    result.errors.add("E2003 " + path + ".cells: 每个单元格必须是 [左, 上, 右, 下]（百分比）")
                    continue
                }
                out.add(Rect(left: readIntOr(cell[0], path + ".cells", result),
                    top: readIntOr(cell[1], path + ".cells", result),
                    right: readIntOr(cell[2], path + ".cells", result),
                    bottom: readIntOr(cell[3], path + ".cells", result)))
            case _ => result.errors.add("E2002 " + path + ".cells: 元素必须是数组")
        }
    }
    return out.toArray()
}

func readIntOr(v: JsonValue, path: String, result: LoadResult): Int32 {
    match (jsonAsInt(v)) {
        case Some(n) => Int32(n)
        case None =>
            result.errors.add("E2002 " + path + ": 元素必须是整数")
            0
    }
}

func readSize(items: ArrayList<JsonValue>, path: String, result: LoadResult): Option<Size> {
    if (items.size != 2) {
        result.errors.add("E2003 " + path + ".size: 必须恰好两个元素 [宽, 高]")
        return None
    }
    let w = readPercent(items[0], path + ".size[0]", result)
    let h = readPercent(items[1], path + ".size[1]", result)
    match ((w, h)) {
        case (Some(a), Some(b)) => Some(Size(width: a, height: b))
        case _ => None
    }
}

func readPercent(v: JsonValue, path: String, result: LoadResult): Option<Int32> {
    match (v) {
        case JStr(s) =>
            var t = s.trimAscii()
            if (t.endsWith("%")) {
                t = t[0..t.size - 1]
            }
            match (tryParseInt(t)) {
                case Some(n) => Some(Int32(n))
                case None =>
                    result.errors.add("E2003 " + path + ": 无法解析尺寸 \"" + s + "\"，示例：\"50%\"")
                    None
            }
        case JInt(n) => Some(Int32(n))
        case _ =>
            result.errors.add("E2002 " + path + ": 必须是字符串或整数")
            None
    }
}

func readMonitorSelector(s: String, path: String, result: LoadResult): MonitorSelector {
    match (s.toAsciiLower()) {
        case "primary" => MonitorSelector.Primary
        case "secondary" => MonitorSelector.Secondary
        case _ =>
            match (tryParseInt(s)) {
                case Some(n) => MonitorSelector.Index(n)
                case None =>
                    result.errors.add("E2003 " + path + ".monitor: 取值必须是 primary/secondary/索引")
                    MonitorSelector.Primary
            }
    }
}

func readAnchor(s: String, path: String, result: LoadResult): AnchorKind {
    match (s.toAsciiLower()) {
        case "left" => AnchorKind.Left
        case "right" => AnchorKind.Right
        case "top" => AnchorKind.Top
        case "bottom" => AnchorKind.Bottom
        case "top-left" => AnchorKind.TopLeft
        case "top-right" => AnchorKind.TopRight
        case "bottom-left" => AnchorKind.BottomLeft
        case "bottom-right" => AnchorKind.BottomRight
        case "center" => AnchorKind.Center
        case _ =>
            result.errors.add("E2003 " + path + ".anchor: 未知的锚点 \"" + s + "\"")
            AnchorKind.Left
    }
}

// ---------- 组与启动集合 ----------

func parseGroups(m: HashMap<String, JsonValue>, result: LoadResult) {
    for ((id, value) in m) {
        let path = "groups." + id
        match (value) {
            case JObj(o) =>
                let g = GroupDef()
                g.id = id
                g.name = id
                match (o.get("name")) {
                    case Some(JStr(s)) => g.name = s
                    case Some(_) => result.errors.add("E2002 " + path + ".name: 必须是字符串")
                    case None => ()
                }
                match (o.get("layout")) {
                    case Some(JStr(s)) => g.layoutId = s
                    case Some(_) => result.errors.add("E2002 " + path + ".layout: 必须是字符串")
                    case None => ()
                }
                g.appIds = readStringArray(o, "apps", path, result)
                match (o.get("monitor")) {
                    case Some(JStr(s)) => g.monitor = readMonitorSelector(s, path, result)
                    case Some(JInt(v)) => g.monitor = MonitorSelector.Index(v)
                    case Some(_) => result.errors.add("E2002 " + path + ".monitor: 必须是字符串或整数")
                    case None => ()
                }
                match (o.get("activate")) {
                    case Some(JStr(s)) =>
                        match (s.toAsciiLower()) {
                            case "focus-last" => g.activate = ActivatePolicy.FocusLast
                            case "focus-first" => g.activate = ActivatePolicy.FocusFirst
                            case "cycle" => g.activate = ActivatePolicy.Cycle
                            case _ => result.errors.add("E2003 " + path + ".activate: 取值必须是 focus-last/focus-first/cycle")
                        }
                    case Some(_) => result.errors.add("E2002 " + path + ".activate: 必须是字符串")
                    case None => ()
                }
                match (o.get("onSwitchAway")) {
                    case Some(JStr(s)) =>
                        match (s.toAsciiLower()) {
                            case "minimize" => g.onSwitchAway = SwitchAwayPolicy.Minimize
                            case "hide" => g.onSwitchAway = SwitchAwayPolicy.Hide
                            case "keep" => g.onSwitchAway = SwitchAwayPolicy.Keep
                            case _ => result.errors.add("E2003 " + path + ".onSwitchAway: 取值必须是 minimize/hide/keep")
                        }
                    case Some(_) => result.errors.add("E2002 " + path + ".onSwitchAway: 必须是字符串")
                    case None => ()
                }
                match (o.get("onActivate")) {
                    case Some(JStr(s)) =>
                        match (s.toAsciiLower()) {
                            case "restore" => g.onActivate = RestorePolicy.Restore
                            case "keep-size" => g.onActivate = RestorePolicy.KeepSize
                            case _ => result.errors.add("E2003 " + path + ".onActivate: 取值必须是 restore/keep-size")
                        }
                    case Some(_) => result.errors.add("E2002 " + path + ".onActivate: 必须是字符串")
                    case None => ()
                }
                result.snapshot.groups.add(id, g)
                result.snapshot.groupOrder.add(id)
            case _ => result.errors.add("E2002 " + path + ": 必须是对象")
        }
    }
}

func parseLaunches(m: HashMap<String, JsonValue>, result: LoadResult) {
    for ((id, value) in m) {
        let path = "launches." + id
        match (value) {
            case JObj(o) =>
                let l = LaunchSpec()
                l.id = id
                l.apps = readStringArray(o, "apps", path, result)
                if (l.apps.size == 0) {
                    result.errors.add("E2003 " + path + ".apps: 缺少必填字段 apps（至少一个应用）")
                }
                match (o.get("staggerMs")) {
                    case Some(JInt(v)) => l.staggerMs = v
                    case Some(_) => result.errors.add("E2002 " + path + ".staggerMs: 必须是整数")
                    case None => ()
                }
                match (o.get("group")) {
                    case Some(JStr(s)) => l.group = s
                    case Some(_) => result.errors.add("E2002 " + path + ".group: 必须是字符串")
                    case None => ()
                }
                match (o.get("layout")) {
                    case Some(JStr(s)) => l.layout = s
                    case Some(_) => result.errors.add("E2002 " + path + ".layout: 必须是字符串")
                    case None => ()
                }
                result.snapshot.launches.add(id, l)
                result.snapshot.launchOrder.add(id)
            case _ => result.errors.add("E2002 " + path + ": 必须是对象")
        }
    }
}

// ---------- 交叉引用校验 ----------

func crossCheck(result: LoadResult) {
    let snap = result.snapshot
    for (id in snap.groupOrder) {
        let g = snap.groups[id]
        if (!g.layoutId.isEmpty() && !snap.layouts.contains(g.layoutId)) {
            result.errors.add("E2007 groups." + id + ".layout: 引用了不存在的布局 \"" + g.layoutId + "\"")
        }
        for (a in g.appIds) {
            if (!snap.apps.contains(a)) {
                result.errors.add("E2007 groups." + id + ".apps: 引用了不存在的应用 \"" + a + "\"")
            }
        }
    }
    for (id in snap.launchOrder) {
        let l = snap.launches[id]
        for (a in l.apps) {
            if (!snap.apps.contains(a)) {
                result.errors.add("E2007 launches." + id + ".apps: 引用了不存在的应用 \"" + a + "\"")
            }
        }
        if (!l.group.isEmpty() && !snap.groups.contains(l.group)) {
            result.errors.add("E2007 launches." + id + ".group: 引用了不存在的组 \"" + l.group + "\"")
        }
        if (!l.layout.isEmpty() && !snap.layouts.contains(l.layout)) {
            result.errors.add("E2007 launches." + id + ".layout: 引用了不存在的布局 \"" + l.layout + "\"")
        }
    }
    if (!snap.startupGroup.isEmpty() && !snap.groups.contains(snap.startupGroup)) {
        result.errors.add("E2007 behavior.startupGroup: 引用了不存在的组 \"" + snap.startupGroup + "\"")
    }
    if (!snap.defaultLayout.isEmpty() && !snap.layouts.contains(snap.defaultLayout)) {
        result.errors.add("E2007 behavior.defaultLayout: 引用了不存在的布局 \"" + snap.defaultLayout + "\"")
    }
}

// ---------- 小工具 ----------

func report(result: LoadResult, code: String, path: String, message: String) {
    let line = code + " " + path + ": " + message
    if (result.snapshot.strict) {
        result.errors.add(line)
    } else {
        result.warnings.add(line)
    }
}

func containsString(arr: Array<String>, s: String): Bool {
    for (a in arr) {
        if (a == s) {
            return true
        }
    }
    return false
}

func readStringArray(o: HashMap<String, JsonValue>, key: String, path: String, result: LoadResult): Array<String> {
    match (o.get(key)) {
        case Some(JArr(items)) =>
            let out = ArrayList<String>()
            for (it in items) {
                match (it) {
                    case JStr(s) => out.add(s)
                    case _ => result.errors.add("E2002 " + path + "." + key + ": 元素必须是字符串")
                }
            }
            return out.toArray()
        case Some(JStr(s)) => return [s]
        case Some(_) =>
            result.errors.add("E2002 " + path + "." + key + ": 必须是字符串数组")
            return []
        case None => return []
    }
}

public func tryParseInt(s: String): Option<Int64> {
    let t = s.trimAscii()
    if (t.isEmpty()) {
        return None
    }
    for (b in t.toArray()) {
        if (b < 0x30 || b > 0x39) {
            if (!(b == 0x2D && t.size > 1)) {
                return None
            }
        }
    }
    try {
        return Some(Int64.parse(t))
    } catch (e: Exception) {
        return None
    }
}
