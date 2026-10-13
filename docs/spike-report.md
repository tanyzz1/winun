# M0 技术验证报告（winun）

| 项目 | 内容 |
| --- | --- |
| 验证日期 | 2026-10-07 |
| 工具链 | Cangjie Compiler 1.0.5 (cjnative)，Target: x86_64-w64-mingw32 |
| 运行环境 | Windows，仓颉 SDK 位于 `C:\Program Files (x86)\Cangjie`（MinGW + LLVM 后端） |
| 验证方式 | `spike/` 最小工程逐步加码 + 真实运行输出 |

## 1. 结论摘要

| # | 验证项 | 结论 | 证据 |
| --- | --- | --- | --- |
| S-1 | 工具链可用 | 通过 | `cjc -v` = 1.0.5 (cjnative)；`cjpm build/test` 正常 |
| S-2 | FFI 链接系统 DLL | 通过 | `link-option = "-LC:/Windows/System32 -luser32 -lkernel32"`，直接链接 System32 下的 DLL |
| S-3 | 调用约定 | 通过 | `@CallingConv[STDCALL]` 可用于 `foreign func` 与回调；x64 下与 CDECL 等价 |
| S-4 | `@C struct` 布局 | 通过 | `sizeOf<RECT>() == 16`；`GetWindowRect` 写回 `(-7,-7,2055,1239)` 与真实最大化窗口一致 |
| S-5 | `Bool` 返回值映射 | 通过 | 双向验证：`IsWindow(有效句柄)=true`、`IsWindow(null)=false` |
| S-6 | `inout` 出参 | 通过 | `GetWindowRect(inout rect)`、`GetMonitorInfoW(inout info)` |
| S-7 | 宽字符 API | 通过 | `GetWindowTextW` 返回 35（前台窗口标题长度） |
| S-8 | 数组裸指针 | 通过 | `acquireArrayRawData(arr)` → `handle.pointer` → 传给 `CPointer<UInt16>` 参数；用完 `releaseArrayRawData` |
| S-9 | Win32 回调 | 通过 | `@C @CallingConv[STDCALL] func enumProc(...)` 被 `EnumWindows` 调用：一次枚举到 977 个顶层窗口、30 个可见 |
| S-10 | 进程启动 | 通过 | `WinExec("notepad.exe")` 返回 33；`CreateProcessW` 封装已编译进 `win32` 包 |

## 2. 踩到的坑（对设计有强制影响）

### 2.1 `main(args: Array<String>)` 访问参数会挂起

- 现象：`main(args: Array<String>)` 中任何对 `args` 的访问（甚至 `args.size`）都会让进程永久阻塞，且不输出任何内容；改成 `main()` 立即正常。
- 规避：入口改为 `main()`，命令行通过 Win32 自行获取：`GetCommandLineW()` + `WideCharToMultiByte(CP_UTF8, ...)`，再按 Windows 规则拆分（`winun.win32.splitWindowsCommandLine`，带单测）。
- 影响：`src/main.cj` 不再依赖运行时 argv；该拆分函数是纯函数，可单测。

### 2.2 `GetLastError` / `SetLastError` 在本环境不可用

- 现象：`SetLastError(1234)` 之后立刻 `GetLastError()` 返回 **0**；失败的 `LoadLibraryW` 之后同样返回 0。
- 结论：错误诊断不能只依赖 `GetLastError`。当前实现以「返回值 + API 名」为准记录日志，必要时（M3）引入 `native/` 下的 C shim 返回结构化错误码。

### 2.3 沙箱限制的真实边界（结论已修正）

- **跨进程**窗口操作被拦截：`SetWindowPos`/`MoveWindow` 作用于其它进程的窗口（前台窗口、记事本）时返回 FALSE；这是沙箱真正限制的部分。
- **本进程**的窗口完全可用：`RegisterClassExW` + `CreateWindowExW` 建窗口成功，`SetWindowPos` 移动自己创建的窗口成功且读回一致 → 据此实现 `winun selftest`，在沙箱内用真实 Win32 调用链验证布局执行路径。
- `RegisterHotKey` **可用**：`win+alt+q`/`win+alt+f11`/`win+alt+f12`/`ctrl+alt+f11` 均注册成功；最初判定为“被沙箱拦截”是因为只试了 `win+alt+1`，而该组合键（连同 `win+alt+2`、`win+alt+3`、`win+alt+tab`）在本机确实已被其它程序占用，加之 `GetLastError` 恒为 0 无法区分原因，导致误判。
- 经验：**同一结论至少要用一组变量验证**；错误码不可用时，必须靠“换一组输入”来区分“被限制”与“被占用”。

### 2.4 语言细节（写代码时的硬约束）

| 细节 | 说明 |
| --- | --- |
| 整型字面量默认 `Int64` | 传给 FFI 的 `Int32` 形参必须显式标注，例如 `let id: Int32 = 1` |
| 数组下标必须是 `Int64` | `for (i in 0..n)` 中若 `n` 是 `Int32`，需写成 `0..Int64(n)` |
| 元组取元素用下标 | `t[0]`，不是 `t.0` |
| `CPointer` 转换单向 | 只有 `ptr.toUIntNative()`；整数反向构造指针不被允许 → `win32` 用 id ↔ HWND 表 |
| `CPointer` 不能作 `HashMap` 键 | 泛型约束不满足 → 以 `Int64`（地址）或句柄表为键 |
| `foreign func` 不能带 `public` | 与 `public` 冲突；需要在包外暴露时写公开包装函数（见 `win32/pump.cj`） |
| `CFunc` lambda 不能捕获变量 | 回调必须是顶层 `@C` 函数，上下文放包级变量（`Mutex` 保护） |
| 简单枚举不支持 `==` | 用 `match` 比较，或为枚举派生 `Equatable` |
| 多行字符串 `"""..."""` 会处理转义 | 写 JSON 样例时 `\\` 会变成 `\`；测试里可用 `String.fromUtf8([0x5C])` 构造反斜杠 |
| 常量数组要写 `let` | `const` 只接受编译期常量（可用 `VArray`） |
| `File.appendTo(path, data)` | 第二个参数是 `Array<UInt8>`，不是 `String` |
| Windows 中文路径 | `cjpm` 不支持，仓库必须放在纯 ASCII 路径下 |

## 3. 产物

- `spike/`：最小验证工程（FFI 冒烟、`EnumWindows` 回调、进程启动、窗口操作）。
- 正式工程：`cjpm build` 通过；`cjpm test` 33 个用例全绿；`main.exe selftest` 16 项全过；`main.exe validate --config config/winun.json` → `配置有效：apps=5 launches=3 layouts=5 groups=3 hotkeys=14`。

## 4. 遗留验证项（需在普通交互会话中执行）

| # | 项目 | 验收标准 |
| --- | --- | --- |
| V-1 | 热键闭环（真实按键） | 注册能力已由 `selftest` 覆盖；此处验证“真按键 → WM_HOTKEY → 动作”：按热键后日志出现启动记录（注意先换掉被占用的组合键） |
| V-2 | 布局执行 | 记事本窗口被移动到屏幕左半区（`SetWindowPos` 生效） |
| V-3 | 组切换 | `Win+Alt+Tab` 在三个组之间轮转，旧组窗口按 `onSwitchAway` 最小化/隐藏 |
| V-4 | 双屏与 DPI | 150% 缩放下布局不偏移，`monitor` 选择生效 |

## 5. 复现命令

```powershell
. "C:\Program Files (x86)\Cangjie\envsetup.ps1"
cd <仓库路径>
cjpm build
cjpm test
.\target\release\bin\main.exe smoke                      # 纯逻辑自检（配置/布局/组合键/UTF-16）
.\target\release\bin\main.exe validate --config config\winun.json
.\target\release\bin\main.exe list windows
```