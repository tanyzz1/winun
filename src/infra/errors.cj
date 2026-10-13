package winun.infra

public class WinunError <: Exception {
    public let code: String

    public init(code: String, message: String) {
        super(message)
        this.code = code
    }
}

public class JsonError <: Exception {
    public let line: Int64
    public let column: Int64

    public init(message: String, line: Int64, column: Int64) {
        super(message)
        this.line = line
        this.column = column
    }
}

public class ConfigError <: Exception {
    public let code: String
    public let path: String

    public init(code: String, path: String, message: String) {
        super(message)
        this.code = code
        this.path = path
    }
}
