package winun

import winun.cli.*
import winun.win32.*

main(): Int64 {
    let args = commandLineArgs()
    try {
        return runCli(args)
    } catch (e: Exception) {
        // 兜底：任何未预期异常都不应该以原始堆栈形式抛给用户
        println("[错误] 未预期的异常：" + e.message)
        println("       请附上日志（%APPDATA%\\winun\\logs\\winun.log）反馈；退出码 4")
        return 4
    }
}
