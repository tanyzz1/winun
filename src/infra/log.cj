package winun.infra

import std.collection.*
import std.fs.*
import std.time.*

public enum LogLevel {
    | Debug
    | Info
    | Warn
    | Error
}

public func parseLogLevel(s: String): Option<LogLevel> {
    match (s.toAsciiLower()) {
        case "debug" => Some(LogLevel.Debug)
        case "info" => Some(LogLevel.Info)
        case "warn" => Some(LogLevel.Warn)
        case "error" => Some(LogLevel.Error)
        case _ => None
    }
}

public func logLevelName(l: LogLevel): String {
    match (l) {
        case LogLevel.Debug => "DEBUG"
        case LogLevel.Info => "INFO"
        case LogLevel.Warn => "WARN"
        case LogLevel.Error => "ERROR"
    }
}

public class Logger {
    var level: LogLevel
    var filePath: String
    var toConsole: Bool
    var fileWritable: Bool = true
    let lines: ArrayList<String> = ArrayList<String>()

    public init(level: LogLevel, filePath: String, toConsole: Bool) {
        this.level = level
        this.filePath = filePath
        this.toConsole = toConsole
    }

    // 首次写入失败时（多半是目录不存在）尝试补建目录并重试一次；
    // Directory.create 对已存在目录的行为在平台上不一致，因此不预判、只看实际写入结果
    func tryAppend(line: String): Bool {
        try {
            File.appendTo(this.filePath, (line + "\r\n").toArray())
            return true
        } catch (e: Exception) {
            return false
        }
    }

    public func log(l: LogLevel, scope: String, message: String) {
        if (rank(l) < rank(this.level)) {
            return
        }
        let line = timestamp() + " [" + logLevelName(l) + "] [" + scope + "] " + message
        this.lines.add(line)
        if (this.toConsole) {
            println(line)
        }
        if (!this.filePath.isEmpty() && this.fileWritable) {
            if (!this.tryAppend(line)) {
                let dir = parentDirOf(this.filePath)
                if (!dir.isEmpty()) {
                    try {
                        Directory.create(dir, recursive: true)
                    } catch (e: Exception) {
                        ()
                    }
                }
                if (!this.tryAppend(line)) {
                    this.fileWritable = false
                    if (this.toConsole) {
                        println("[warn] 日志文件不可写，后续只输出到控制台：" + this.filePath)
                    }
                }
            }
        }
    }

    public func debug(scope: String, message: String) { this.log(LogLevel.Debug, scope, message) }
    public func info(scope: String, message: String) { this.log(LogLevel.Info, scope, message) }
    public func warn(scope: String, message: String) { this.log(LogLevel.Warn, scope, message) }
    public func error(scope: String, message: String) { this.log(LogLevel.Error, scope, message) }
}

func rank(l: LogLevel): Int64 {
    match (l) {
        case LogLevel.Debug => 0
        case LogLevel.Info => 1
        case LogLevel.Warn => 2
        case LogLevel.Error => 3
    }
}

func timestamp(): String {
    let now = DateTime.now()
    return now.toString()
}