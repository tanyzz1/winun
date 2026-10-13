package winun.infra

import std.fs.*

public func fileExists(path: String): Bool {
    try {
        let _ = File.readFrom(path)
        return true
    } catch (e: Exception) {
        return false
    }
}

public func readTextFile(path: String): String {
    let bytes = File.readFrom(path)
    return String.fromUtf8(bytes)
}

public func writeTextFile(path: String, text: String): Unit {
    File.writeTo(path, text.toArray())
}
