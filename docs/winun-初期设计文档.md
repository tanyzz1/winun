# winun 初期设计文档

| 项目 | 内容 |
| --- | --- |
| 文档版本 | v0.2 |
| 文档状态 | 待评审 |
| 变更说明 | v0.2：配置格式由 INI 改为 JSON |
| 编写日期 | 2026-10-07 |
| 适用阶段 | M0 技术验证 ~ M2 功能开发 |
| 实现语言 | 仓颉（Cangjie），CJNative 后端，Windows x64 |
| 配套文档 | 后续拆分出 `docs/config-reference.md`、`docs/adr/*.md`、`docs/testing.md` |

---

## 1. 项目概述

### 1.1 一句话定位

**winun** 是一个用仓颉语言编写、常驻 Windows 后台的**配置驱动窗口管理器**：用户用一份 JSON 配置文件（`winun.json`）声明"启动哪些应用、窗口怎么摆、怎么分组"，winun 通过**全局快捷键**完成应用的启动、窗口的布局、分组的切换。

### 1.2 命名

- **winun** = Windows + Union，取"把多个窗口联合成一个工作单元"之意，对应核心能力——窗口组合（Group）。
- 工作目录名 `winini` 为仓库历史命名，与配置格式无关；配置统一为单文件 JSON（`winun.json`，见第 7 章）。
- 产物名：`winun.exe`；运行期目录：`%APPDATA%\winun\`（配置、日志、状态）。

### 1.3 典型场景（用户故事）

- **US-1 一键进入工作态**：按 `Win+Alt+1`，winun 拉起 VS Code、两个终端、Chrome，等窗口出现后按"主区 + 侧栏"布局摆好，并进入 `coding` 组。
- **US-2 一键进入会议态**：按 `Win+Alt+2`，拉起 Teams/腾讯会议并最大化到主显示器，其余窗口最小化。
- **US-3 组间切换**：按 `Win+Alt+Tab` 在 `coding` / `browser` / `meeting` 三组之间轮转，旧组窗口按配置最小化或隐藏，新组窗口恢复并聚焦到上次焦点窗口。
- **US-4 临时收编**：手动打开的窗口，按 `Win+Alt+Q` 收进当前组，并立即参与本组布局。
- **US-5 改配置即生效**：改完 `winun.json` 保存，winun 热重载，下一次切换或按 `Win+Alt+R` 立即重新布局。

### 1.4 范围（做什么 / 不做什么）

**做（v0.1 ~ v0.3）**

- 全局快捷键注册、冲突检测、按组切换。
- 按配置文件启动应用（可执行文件、参数、工作目录、环境变量）。
- 窗口识别（进程路径、窗口类名、标题正则）与生命周期跟踪。
- 布局引擎：网格、比例分栏、绝对坐标、贴边/半屏、最大化、多显示器、DPI 感知。
- 窗口分组（Group）：组的定义、收编、切换、组内焦点策略。
- 配置校验、热重载、日志、单实例、开机自启。

**不做（明确排除，避免范围蔓延）**

- 不注入 DLL、不 Hook 其它进程、不修改他人窗口的绘制。
- 不做完整的平铺窗口管理器（不强制接管全部新窗口，只接管"配置声明过"的窗口）。
- 不做跨平台（但平台层用 trait 隔离，为将来留口子）。
- v0.1 不做图形设置界面（配置即界面，后续可加托盘菜单）。
- v0.1 不碰未公开 COM（虚拟桌面 `IVirtualDesktopManager`）与键盘钩子。

### 1.5 术语表

| 术语 | 含义 |
| --- | --- |
| HWND | Win32 窗口句柄，winun 中作为窗口的身份标识（对应仓颉 `CPointer<Unit>`） |
| WindowInfo | 领域层的窗口元数据快照：句柄、PID、进程路径、类名、标题、可见性、显示器 |
| AppSpec | 一个可启动应用的描述（exe、args、cwd、env、匹配规则） |
| Placement | 一次布局解算的结果：目标矩形 + 显示状态（普通/最大化/最小化） |
| LayoutSpec | 布局声明（网格/比例/绝对…），来自配置文件 |
| Group | 一组窗口 + 一套布局 + 一个切换策略，是"窗口组合"的载体 |
| Chord | 一个组合键（修饰键集合 + 主键），如 `Win+Alt+1` |
| Action | 由 Chord 触发的动作（启动、切换组、布局、移动窗口…） |
| Registry | 运行期索引：HWND → WindowInfo、AppId → 窗口集合、Group → 窗口集合 |

---

## 2. 需求分解

### 2.1 功能需求

| 编号 | 需求 | 关键点 | 优先级 |
| --- | --- | --- | --- |
| FR-1 | 全局快捷键注册 | 与主消息循环同线程；冲突时给出明确日志而非静默失败 | P0 |
| FR-2 | 按配置启动应用 | 支持参数/工作目录/环境变量；启动后等待窗口出现并可收编 | P0 |
| FR-3 | 窗口大小与位置管理 | 布局解算与执行分离；幂等（重复执行结果一致） | P0 |
| FR-4 | 窗口分组与组合 | 组的定义、收编、移出、组级布局 | P0 |
| FR-5 | 快捷键切换组 | 循环切换、指定切换、焦点轮转、旧组窗口处理策略 | P0 |
| FR-6 | 配置校验（JSON） | `winun validate` 对 `winun.json` 输出全部错误（含 file:line:column），退出码非 0 | P1 |
| FR-7 | 配置热重载 | `winun.json` 变更 → 解析 → 差量应用（重注册快捷键、更新组） | P1 |
| FR-8 | 多显示器与 DPI | 显示器枚举、工作区（排除任务栏）、Per-Monitor V2 | P1 |
| FR-9 | 单实例与开机自启 | 命名互斥体；注册表 Run 项或启动文件夹 | P2 |
| FR-10 | 托盘/命令行交互 | v0.1 只做命令行与日志，托盘后置 | P2 |

### 2.2 非功能需求

| 编号 | 需求 | 验收口径 |
| --- | --- | --- |
| NFR-1 | 响应速度 | 热键到窗口开始移动 < 150 ms（不含被启动应用的自身耗时） |
| NFR-2 | 常驻开销 | 空转内存 < 50 MB，CPU 空闲 ≈ 0（消息循环阻塞等待） |
| NFR-3 | 稳定性 | 单个窗口操作失败不得导致进程退出；所有 Win32 调用检查返回值并记录 `GetLastError` |
| NFR-4 | 可测性 | 布局引擎、配置解析、键位解析为纯函数，可在无 Windows 依赖下单测 |
| NFR-5 | 可观测性 | 文件日志分级（error/warn/info/debug），可 `--console` 附着控制台 |
| NFR-6 | 可移植性（弱） | 领域层不出现任何 Win32 类型；平台差异收敛在 `winun.platform` 之后 |

---

## 3. 总体架构

### 3.1 分层

    ┌──────────────────────────────────────────────────────────────┐
    │ L5 宿主层      app / cli       入口、装配、消息循环、子命令      │
    ├──────────────────────────────────────────────────────────────┤
    │ L4 编排层      core            ActionDispatcher、Registry、    │
    │                                Session（组状态机）、Scheduler  │
    ├──────────────────────────────────────────────────────────────┤
    │ L3 领域层      domain / layout 窗口模型、组模型、动作模型、      │
    │                                纯函数布局引擎                  │
    ├──────────────────────────────────────────────────────────────┤
    │ L2 配置层      config          JSON 解析、模型映射、校验、重载   │
    ├──────────────────────────────────────────────────────────────┤
    │ L1 平台抽象    platform        trait：WindowBackend / Hotkey / │
    │                                Launcher / Monitor / Clock     │
    ├──────────────────────────────────────────────────────────────┤
    │ L0 平台实现    win32           FFI 声明 + 安全封装 + 句柄管理    │
    ├──────────────────────────────────────────────────────────────┤
    │ L-1 基础设施   infra           日志、UTF-8/UTF-16、错误、计时、  │
    │                                JSON 词法、文件监听              │
    └──────────────────────────────────────────────────────────────┘

**依赖规则（强制）**

1. 依赖只能自上而下（L5 → L0），禁止反向依赖。
2. 领域层（L3）与配置层（L2）不得 import `winun.win32`，只依赖 `winun.platform` 的 trait。
3. 仓颉的包（package）**不允许循环依赖**，`cjpm` 会在构建时直接报错，因此分层必须在包级别严格落地（见 5.2 依赖矩阵）。
4. L0 之外不得出现 `unsafe` 与 `CPointer`；指针与内存生命周期只在 L0 内部管理，对外暴露领域类型。

### 3.2 关键架构决策（ADR 摘要）

| 编号 | 决策 | 备选 | 结论与理由 |
| --- | --- | --- | --- |
| ADR-01 | 用仓颉 FFI 直连 Win32（不写 C 中间层） | 全部下沉到自建 C DLL | v0.1 直连：仓颉的 `foreign func`/`@C struct`/`CFunc` 已能覆盖 user32/kernel32 的调用约定与结构体；仅当引入未公开 COM、键盘钩子、复杂回调时才新增 `native/` 下的 shim（用 `[ffi.c]` 挂载） |
| ADR-02 | 配置文件用 **JSON**（单文件 `winun.json`）+ 自研严格 JSON 解析器（约 500 行、零依赖、带行列号错误定位） | TOML / YAML / `stdx.encoding.json` | JSON 能自然表达 `apps`/`launches`/`layouts`/`groups` 的嵌套结构，并拥有 JSON Schema 与编辑器校验生态；仓颉标准库不含 JSON，故自研解析器（约 500 行、零依赖、可单测）；`stdx.encoding.json` 作为可选替代，但**默认不引入**，以规避 stdx 的跨版本兼容风险。原 INI 方案已废弃（历史说明，仅本节保留） |
| ADR-03 | 主线程独占消息循环与窗口操作 | 多线程并行操作窗口 | `RegisterHotKey` 的消息投递到注册线程；`SetForegroundWindow` 受前台锁定规则约束，多线程更易失败。所有会触碰窗口的操作统一投递回主线程执行 |
| ADR-04 | 窗口"组合"用**自建组模型 + 批量显隐/布局** | SetParent 容器窗口 / 未公开 COM 虚拟桌面 | SetParent 跨进程会带来输入法、DPI、最小化动画异常；未公开 COM 有版本风险。自建组模型零侵入、可回滚，风险最低 |
| ADR-05 | 布局"解算"与"执行"分离 | 边算边设 | 解算为纯函数（输入窗口集合 + 布局 + 工作区，输出 Placement 数组），可单测、可回放、可 dry-run 打印 |
| ADR-06 | 日志自研轻量实现 | stdx.log | stdx 需单独下载且不承诺跨版本兼容；winun 日志需求简单（分级 + 文件 + 轮转），自研成本低于依赖成本 |
| ADR-07 | 内部统一使用宽字符（W 系列 API） | A 系列 + ANSI 代码页 | 中文 Windows 的 ANSI 代码页为 GBK，直接传 UTF-8 会乱码；统一 UTF-16（`CPointer<UInt16>`）+ 自研 UTF-8↔UTF-16 转换，避免代码页依赖 |

### 3.3 线程与并发模型

| 线程 | 职责 | 约束 |
| --- | --- | --- |
| T0 主线程 | `GetMessageW` 消息循环、`RegisterHotKey`、所有窗口操作（SetWindowPos/ShowWindow/SetForegroundWindow）、`SetWinEventHook` 回调落入 | 唯一允许注册热键与操作窗口的线程；循环阻塞，需被唤醒 |
| T1 工作线程 | 事件队列消费、应用启动（`CreateProcessW` + 等待窗口）、`winun.json` 热重载、日志落盘 | 不直接操作窗口；需要的窗口动作包装成命令投递给 T0 |
| T2（可选）定时线程 | 布局节流/防抖、窗口出现超时检测 | 可用 `std.time.sleep` + 循环实现，暂不引入额外机制 |

**跨线程通信**

- T1 → T0：`ConcurrentLinkedQueue<Command>` 入队后调用 `PostThreadMessageW(mainThreadId, WM_APP + 1, 0, 0)` 唤醒阻塞中的 `GetMessageW`。
- 事件回调（`@C func`，运行在 Win32 回调上下文）只做一件事：把事件投进队列，绝不做布局与文件 IO。

---

## 4. 技术可行性（仓颉 × Win32）

### 4.1 工具链与环境

| 项 | 结论 |
| --- | --- |
| 语言 | 仓颉（Cangjie）CJNative 后端 |
| 工具链 | `cjc`（编译器）、`cjpm`（包管理与构建）、`cjfmt`、`cjlint`、`cjcov` |
| 平台 | Windows x64；官方提供 `cangjie-sdk-windows-x64-*.exe/zip` 安装包 |
| 已知平台差异 | 官方明确说明"当前 Windows 平台上的仓颉编译器基于 **MinGW** 实现，相较于 Linux 版本功能会有部分欠缺"——因此链接方式与部分工具能力需要在 M0 先行验证 |
| 目录约束 | `cjpm` 在 Windows 平台**不支持中文路径**，项目与配置路径必须为纯 ASCII（当前工作目录满足） |
| SDK 依赖 | 尽量只用标准库（`std.core/fs/io/collection/sync/regex/time/process/env/argopt/unicode/convert/unittest`），暂不引入 `stdx` |

### 4.2 仓颉 FFI 能力清单（已验证的机制）

| 能力 | 写法 | winun 中的用途 |
| --- | --- | --- |
| 声明外部函数 | `foreign func SetWindowPos(hWnd: HWND, ...): Bool` | 全部 Win32 API |
| 调用约定 | `@CallingConv[STDCALL]`（Win32 API 约定）/ `CDECL`（默认） | 回调定义；x64 下两者等价，仍显式标注以便阅读 |
| C 结构体 | `@C struct RECT { public var left: Int32 = 0 ... }` | `RECT`/`POINT`/`MSG`/`WINDOWPLACEMENT`/`MONITORINFO`/`STARTUPINFOW` |
| C 函数指针 | `CFunc<(HWND, UInt32, UInt64, UInt64) -> Int64>` | `WNDPROC`、`WINEVENTPROC`、`EnumWindowsProc` |
| 导出给 C 调用 | `@C func onMessage(...)`（顶层非泛型函数） | 回调实现 |
| 指针 / 字符串 | `CPointer<T>`、`CString`、`LibC.mallocCString` / `LibC.free` | 句柄、宽字符串缓冲、结构体出入参 |
| 引用传参 | 调用处 `inout` 表达式 | `GetWindowRect(inout rect)` 等出参风格 API |
| 尺寸内省 | `sizeOf<T>()`、`VArray<Byte, $32>` | 校验结构体 ABI 布局、`rgbReserved` 类保留字段 |
| 动态特性 | `unsafe {}` 块 / `unsafe func` | 所有 FFI 调用点 |

参考写法（示意，非最终代码）：

    package winun.win32

    public type HWND = CPointer<Unit>

    @C
    struct RECT {
        public var left: Int32 = 0
        public var top: Int32 = 0
        public var right: Int32 = 0
        public var bottom: Int32 = 0
    }

    @CallingConv[STDCALL]
    foreign func RegisterHotKey(hWnd: HWND, id: Int32, fsModifiers: UInt32, vk: UInt32): Bool

    @CallingConv[STDCALL]
    foreign func SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND,
        X: Int32, Y: Int32, cx: Int32, cy: Int32, uFlags: UInt32): Bool

### 4.3 已知限制与规避策略

| 限制 | 影响 | 规避 |
| --- | --- | --- |
| `CFunc` lambda **不能捕获变量**；`@C` 只能修饰顶层非泛型函数 | 回调无法直接携带上下文 | 全局单例上下文（`Mutex` + 顶层 `var`）；回调只入队不处理业务 |
| 所有 FFI 调用必须在 `unsafe` 上下文 | 代码噪音 | 把 `unsafe` 收敛在 `winun.win32` 一层，对外提供安全函数 |
| FFI 进入 C 函数后栈溢出风险不受仓颉控制 | 极端情况下崩溃 | 需要时调整 `cjStackSize`；避免在回调里做深递归 |
| 包不允许循环依赖 | 结构设计受限 | 用 trait + 依赖倒置（platform 只放接口，core 引用接口，win32 实现接口） |
| Windows 后端基于 MinGW，功能有欠缺 | 链接、调试可能踩坑 | M0 逐项验证（见 4.5），失败则退化为 C shim |
| `cjpm` 不支持中文路径 | 项目路径强约束 | 文档与脚本强制 ASCII 路径 |
| 无官方 GUI 框架 | 做不了原生设置界面 | 配置即界面；后续可用 HTML 配置器或调用系统对话框 |
| UIPI：普通权限进程无法操作管理员窗口 | 部分窗口操作失败 | 检测并记录明确日志；文档提示"以管理员身份运行 winun" |

### 4.4 链接与构建配置

Win32 系统 DLL 通过 `[package].link-option` 透传给链接器（仓颉官方 Windows 示例即用此法链接 `gdi32`）；自研 C 库则通过 `[ffi.c]` 声明"库名 + 路径"。

    # cjpm.toml（草案）
    [package]
      cjc-version = "1.0.0"
      name = "winun"
      version = "0.1.0"
      output-type = "executable"
      src-dir = "src"
      compile-option = "-O2 --warn-off unused"
      link-option = "-LC:/Windows/System32 -luser32 -lkernel32 -lole32 -lshell32 -ladvapi32 -lpsapi -ldwmapi"

    [target.x86_64-w64-mingw32]
      link-option = "-LC:/Windows/System32 -luser32 -lkernel32 -lole32 -lshell32 -ladvapi32 -lpsapi -ldwmapi"

    # 仅在引入自研 C shim 后启用：
    # [ffi.c]
    #   winunshim = { path = "./native/lib/" }

> 说明：target 三元组名（Windows 上为 `x86_64-w64-mingw32`）与可用的 import lib 搜索路径需在 M0 确认；若 `-luser32` 无法解析，退路是显式给出 MinGW import 库目录（`-L<cangjie>/third_party/mingw/...`）或新增 C shim。

### 4.5 M0 技术验证清单（写代码前必须跑通）

| 编号 | 验证项 | 通过标准 |
| --- | --- | --- |
| S-1 | 工具链 | `cjc -v`、`cjpm init/build/run` 在 Windows 上跑通 Hello World |
| S-2 | FFI 链接 | 调用 `GetLastError()`、`MessageBoxW` 成功，`link-option` 能链上 user32/kernel32 |
| S-3 | 热键闭环 | `RegisterHotKey` + `GetMessageW` 收到 `WM_HOTKEY`，按键打印日志 |
| S-4 | 窗口操作 | `EnumWindows` 列出窗口；`SetWindowPos` 改变记事本窗口位置与大小 |
| S-5 | 进程启动 | `CreateProcessW` 拉起记事本；`QueryFullProcessImageNameW` 反查进程路径 |
| S-6 | 宽字符 | 自研 UTF-8↔UTF-16 转换，中文标题读写正确（`GetWindowTextW`） |
| S-7 | 结构体 ABI | `sizeOf<MSG>()`/各结构体尺寸与 C 侧 `sizeof` 一致（48/16/40…） |
| S-8 | 无控制台运行 | 产物以 `-mwindows`（或等价手段）链接后双击不弹黑框，`--console` 可附着控制台 |
| S-9 | 配置文件读取 | 读取含中文、BOM/无 BOM 的 UTF-8 JSON 文件正常 |
| S-10 | 正则 | `std.regex` 能对窗口标题做匹配（用于 AppId 识别） |

M0 产出物：`spike/` 下的最小可运行 demo（热键 → 移动前台窗口到屏幕右半边），作为 M1 的技术基线。

---

## 5. 项目结构

### 5.1 目录树

    winun/
    ├── cjpm.toml                     # 模块配置（名称、版本、链接选项）
    ├── cjpm.lock                     # 依赖锁定（提交到版本库）
    ├── README.md
    ├── docs/
    │   ├── winun-初期设计文档.md       # 本文件
    │   ├── config-reference.md        # 配置字段参考（M1 产出）
    │   ├── testing.md                 # 测试策略（M1 产出）
    │   └── adr/                       # 架构决策记录（从第 3.2 节拆出）
    ├── config/                        # 示例与默认配置（安装时复制到 %APPDATA%\winun）
    │   ├── winun.json                 # 示例配置（v1 规范，见第 7 章）
    │   ├── winun.schema.json          # JSON Schema（编辑器补全与校验）
    │   └── winun.user.json            # 可选覆盖：与 winun.json 深合并，同名键以本文件为准
    ├── src/
    │   ├── main.cj                    # package winun：入口、装配、消息循环
    │   ├── cli/                       # package winun.cli：run/validate/list/version
    │   ├── core/                      # package winun.core：Registry、Dispatcher、Session
    │   ├── domain/                    # package winun.domain：模型与枚举
    │   ├── layout/                    # package winun.layout：解算器与布局实现
    │   ├── config/                    # package winun.config：解析、映射、校验、重载
    │   ├── platform/                  # package winun.platform：trait 与空实现（Null*）
    │   ├── win32/                     # package winun.win32：FFI 与安全封装
    │   └── infra/                     # package winun.infra：log/text/error/fs-watch
    ├── native/                        # 预留：C shim（源码 + 预编译库），M3 之后按需启用
    ├── scripts/
    │   ├── build.ps1                  # 设置环境 + cjpm build + 复制产物
    │   ├── install.ps1                # 安装到 %LOCALAPPDATA%\winun 并注册开机自启
    │   └── run-debug.ps1              # --console 调试启动
    └── target/                        # 构建产物（.gitignore）

**仓颉包规则提醒**

- 模块名 `winun` 即 root 包名；`src/main.cj` 中写 `package winun`。
- 子目录 `src/domain/` 内的文件写 `package winun.domain`，逐级对应。
- 单元测试文件必须以 `_test.cj` 结尾（如 `src/layout/grid_test.cj`），由 `cjpm test` 执行。
- 一个包内可以有多个文件，但同一包内不得出现同名顶层声明。

### 5.2 包职责与依赖矩阵

| 包 | 职责 | 允许依赖 |
| --- | --- | --- |
| `winun`（root） | 进程入口、装配依赖、创建主线程循环、异常兜底 | 全部 |
| `winun.cli` | 参数解析（`std.argopt`）、子命令分发、退出码 | core, config, infra |
| `winun.core` | 动作分发、注册表维护、组会话状态机、命令队列 | domain, layout, config, platform, infra |
| `winun.layout` | 纯函数布局解算（网格/比例/绝对/贴边） | domain, infra |
| `winun.config` | JSON 词法/语法（含行列号）、字段映射与类型校验、语义校验、深合并、热重载 | domain, infra |
| `winun.domain` | 数据模型、枚举、纯逻辑（Chord 解析、AppId 匹配） | infra |
| `winun.platform` | `WindowBackend`/`HotkeyBackend`/`Launcher`/`MonitorService`/`Clock` 接口 + Null 实现 | domain |
| `winun.win32` | FFI 声明、结构体、常量、句柄与内存管理、Win32 实现 | platform, domain, infra |
| `winun.infra` | 日志、UTF-8/UTF-16、错误类型、JSON 词法、文件监听、时间 | 仅标准库 |

### 5.3 命名规范

- 类型：`UpperCamelCase`（`WindowInfo`）；函数/变量：`lowerCamelCase`（`applyLayout`）。
- 常量：`SCREAMING_SNAKE`（`WM_HOTKEY`）或 `static let`。
- 平台层接口一律以 `Backend`/`Service` 结尾；Win32 实现以 `Win32` 前缀（`Win32WindowBackend`）。
- 配置键名：`camelCase`（与 `winun.json` v1 规范严格一致）；配置对象的 id 与动作名：`kebab-case`（`group-activate`、`main-side`）。
- 文件：一个主要类型一个文件，文件名与类型同名（`window_info.cj`）。

---

## 6. 领域模型

### 6.1 核心类型（示意）

    package winun.domain

    // 几何：领域层用自己的结构体；Win32 的 RECT 只在 win32 包内部出现
    public struct Rect {
        public var left: Int32 = 0
        public var top: Int32 = 0
        public var right: Int32 = 0
        public var bottom: Int32 = 0
    }
    public struct Size  { public var width: Int32 = 0; public var height: Int32 = 0 }

    public struct WindowId { public let value: UInt64 }   // HWND 的领域层表示（不透明）

    public class WindowInfo {
        public let id: WindowId
        public var pid: UInt32 = 0
        public var exePath: String = ""        // C:\\...\\Code.exe
        public var exeName: String = ""        // Code.exe
        public var className: String = ""
        public var title: String = ""
        public var rect: Rect = Rect()
        public var monitor: Int32 = 0
        public var visible: Bool = true
        public var minimized: Bool = false
        public var appId: String = ""          // 由匹配规则解析得到
    }

    public enum LayoutKind { Grid | Ratio | Absolute | Anchor | Maximize | Restore }

    public class LayoutSpec {
        public var id: String = ""
        public var kind: LayoutKind = LayoutKind.Grid
        public var columns: Int32 = 1
        public var rows: Int32 = 1
        public var gap: Int32 = 8
        public var margins: Margins = Margins()
        public var ratios: Array<Float64> = []       // 比例分栏
        public var cells: Array<Rect> = []           // 绝对坐标
        public var monitor: MonitorSelector = MonitorSelector.Primary
        public var order: OrderPolicy = OrderPolicy.AsListed
    }

    public enum WindowState { Normal | Maximized | Minimized | Hidden }
    public struct Placement { public let window: WindowId; public let rect: Rect; public let state: WindowState }

    public class GroupDef {
        public var id: String = ""
        public var name: String = ""
        public var layoutId: String = ""
        public var appIds: Array<String> = []
        public var activate: ActivatePolicy = ActivatePolicy.FocusLast
        public var onSwitchAway: SwitchAwayPolicy = SwitchAwayPolicy.Minimize
    }

    public enum Action {
        | Launch(String)                 // launch <set>
        | GroupActivate(String)          // group activate <id>
        | GroupCycle(Int32)              // group cycle next/prev
        | WindowToGroup(String)          // window to-group <id|current>
        | WindowRemoveFromGroup
        | ApplyLayout(String)            // layout apply <id>
        | WindowSnap(SnapTarget)         // window snap left-half
        | WindowFloatToggle
        | WindowFocusCycle(Int32)
        | ReloadConfig
        | Quit
    }

### 6.2 布局引擎（纯函数）

    package winun.layout

    public func solve(targets: Array<WindowInfo>, spec: LayoutSpec,
                      area: WorkArea, dpi: DpiScale): Array<Placement>

- 输入：参与本次布局的窗口（已按 `order` 排序）、布局声明、目标显示器工作区、DPI 缩放。
- 输出：与输入等长的 `Placement` 数组；窗口数多于格子时按"溢出策略"（默认：多余窗口堆叠到最后一个格子中心偏移）。
- 特性：纯函数、无副作用、可在任意平台单测；执行由 `WindowBackend.placeBatch` 完成。
- 附带 `--dry-run` 能力：把 Placement 打印成表格而不执行，便于调布局。

### 6.3 键位解析

- 写法：`<mod>+<mod>+...+<key>`，修饰键 `win|ctrl|alt|shift`（大小写不敏感），主键见附录 B。
- 解析结果 `Chord { modifiers: UInt32, vk: UInt32 }`，直接映射为 `RegisterHotKey` 的 `fsModifiers`/`vk` 参数（`MOD_ALT=0x1, MOD_CONTROL=0x2, MOD_SHIFT=0x4, MOD_WIN=0x8, MOD_NOREPEAT=0x4000`）。
- 同一 Chord 重复绑定 → 配置错误；与系统已占用（注册失败 `ERROR_HOTKEY_ALREADY_REGISTERED=1409`）→ 警告并继续。

---

## 7. 配置系统（JSON）

### 7.1 文件与定位

| 顺序 | 位置 | 说明 |
| --- | --- | --- |
| 1 | `--config <file\|dir>` | 显式指定：给文件则直接使用；给目录则取该目录下的 `winun.json` |
| 2 | `%APPDATA%\winun\winun.json` | 用户配置（`scripts\install.ps1` 首次安装时复制 `config\winun.json`） |
| 3 | 可执行文件同级 `config\winun.json` | 便携模式（解压即用，不写用户目录） |

- **单文件**：v1 的全部配置集中在一个顶层 JSON 对象里（`winun.json`），没有"多文件 + 互相引用"。
- **可选覆盖**：与主配置**同目录**若存在 `winun.user.json`，则把它深合并到主配置之上——对象逐键合并、数组整体替换、标量覆盖；便于把"机器相关"的路径（`exe`、`cwd`）与团队共享的骨架分开存放。
- 主配置缺失或无法读取 → E1001，退出码 2（不做"空配置启动"）。

### 7.2 JSON 约定

| 约定 | 说明 |
| --- | --- |
| 编码 | UTF-8（允许 BOM，解析前剥离）；不接受 UTF-16/GBK |
| 注释 | JSON 标准不支持注释；所有说明写在 `"$comment"` 键里（可出现在任意层级，解析时忽略） |
| 保留键 | 以 `$` 开头的键（`$comment`、`$schema`）一律忽略，不参与"未知键"告警 |
| 环境变量展开 | `%VAR%` 与 `${env:VAR}` 两种写法等价，对所有字符串值生效；未定义的变量按空串替换并告警（`behavior.strict` 为 true 时升级为错误） |
| 键名 | 大小写敏感，必须与 7.3 / 7.4 节完全一致（`maximizeOnStart` ≠ `maximizeonstart`） |
| 类型 | 严格，不做隐式转换：数字不转字符串、`1` ≠ `"1"`、`true` ≠ `1`；整数位出现小数（如 `startupWaitMs: 1.5`）→ 类型错误 |
| 重复键 | 解析器在语法层检测同一对象内的重复键 → E1003（标准 JSON 允许但语义有歧义，这里按错误处理） |
| 未知键 | 默认**警告并忽略**（保证向前兼容）；`behavior.strict = true` 时升级为 E2005 |
| 必填 | 只有顶层 `version` 必填；其余全部可选，缺省取内置默认值 |
| 路径 | 统一 Windows 风格并注意 JSON 转义：JSON 文件中写 `"C:\\Program Files\\App\\app.exe"`（每个反斜杠写成两个），不支持 `~` |

**默认值表**（配置里不写即取此值）

| 位置 | 默认值 |
| --- | --- |
| `log.level` / `log.file` / `log.rotateKb` | `"info"` / `"%APPDATA%\winun\logs\winun.log"` / `2048` |
| `behavior.watchConfig` / `startupGroup` / `defaultLayout` / `commandTimeoutMs` / `strict` | `true` / `null`（不自动切组）/ `null` / `150` / `false` |
| `hotkeys` | `{}`（无热键，此时仅能由 CLI 子命令驱动） |
| `apps.*.args` / `cwd` / `env` | `[]` / exe 所在目录 / `{}` |
| `apps.*.match` | `{}`（退化为按 `exe` 的文件名匹配） |
| `apps.*.startupWaitMs` / `reuse` / `maximizeOnStart` | `8000` / `"existing"` / `false` |
| `launches.*.staggerMs` / `group` / `layout` | `300` / `null` / `null` |
| `layouts.*.type` | `"grid"` |
| `layouts.*.columns` / `rows` / `gap` / `margins` | `1` / `1` / `8` / `[0,0,0,0]` |
| `layouts.*.monitor` / `order` | `"primary"` / `"listed"` |
| `layouts.*.anchor` / `size` | `"center"` / `["50%","50%"]` |
| `groups.*.name` / `layout` / `apps` | 取 groupId 本身 / `behavior.defaultLayout` / `[]` |
| `groups.*.monitor` / `activate` / `onSwitchAway` / `onActivate` | `"primary"` / `"focus-last"` / `"minimize"` / `"restore"` |

### 7.3 顶层结构

| 键 | 类型 | 必需 | 说明 |
| --- | --- | --- | --- |
| `version` | number（整数） | **是** | 配置版本；v1 固定为 `1`，其它值 → E2004 |
| `log` | object | 否 | 日志（字段见 7.4） |
| `behavior` | object | 否 | 全局行为开关 |
| `hotkeys` | object | 否 | 组合键 → 动作字符串 |
| `apps` | object | 否 | 应用定义，键为 `appId`（kebab-case） |
| `launches` | object | 否 | 启动集合，键为 `launchId`（kebab-case） |
| `layouts` | object | 否 | 布局定义，键为 `layoutId`（kebab-case） |
| `groups` | object | 否 | 组定义，键为 `groupId`（kebab-case） |
| `$comment` / `$schema` | string | 否 | 保留键，解析时忽略（说明文字 / 指向 JSON Schema） |

### 7.4 字段参考

**log**

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `level` | 枚举：error、warn、info、debug | `"info"` | 日志级别 |
| `file` | string | `"%APPDATA%\winun\logs\winun.log"` | 日志文件（支持环境变量展开） |
| `rotateKb` | number | `2048` | 单文件超过该大小（KB）滚动为 `.1`，最多保留 3 份 |

**behavior**

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `watchConfig` | bool | `true` | 监听 `winun.json` 变更并热重载 |
| `startupGroup` | string 或 null | `null` | 启动后自动激活的组；引用不存在 → E2001 |
| `defaultLayout` | string 或 null | `null` | 组 / 启动未指定布局时的兜底布局 |
| `commandTimeoutMs` | number | `150` | 单次窗口操作的合理性阈值（用于诊断与降级重试） |
| `strict` | bool | `false` | true：未知键与未定义环境变量按错误处理 |

**hotkeys**

| 键 | 值类型 | 说明 |
| --- | --- | --- |
| `<chord>` | string（动作字符串） | 键为组合键（附录 B 的键名 + win/ctrl/alt/shift），值为动作，例如 `"win+alt+1": "launch dev-env"`；同一 chord 出现两次 → E2002，非法组合键 → E2003 |

动作字符串一览（v1）：

| 动作 | 参数 | 语义 |
| --- | --- | --- |
| `launch <launchId>` | 必需 | 执行启动集合 |
| `group activate <groupId>` | 必需 | 激活指定组 |
| `group cycle next` / `group cycle prev` | 必需 | 组间循环切换 |
| `window to-group <groupId 或 current>` | 必需 | 把前台窗口收进组（`current` = 当前组） |
| `window remove-from-group` | 无 | 把前台窗口移出所在组 |
| `layout apply <layoutId 或 current>` | 必需 | 对当前组重新解算并布局 |
| `window snap <left-half / right-half / top-half / bottom-half / maximize / restore>` | 必需 | 单窗口快照操作 |
| `window float toggle` | 无 | 窗口脱离组布局（浮动） |
| `window focus-cycle next` / `window focus-cycle prev` | 必需 | 组内焦点轮转 |
| `config reload` | 无 | 重新解析并应用配置 |
| `quit` | 无 | 退出 winun |

**apps**（键 `<appId>` 为 kebab-case 字符串）

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `exe` | string | 无（应用对象内**必填**） | 可执行文件绝对路径或 PATH 中的名字；支持 `%VAR%` 与 `${env:VAR}` |
| `args` | array\<string\> | `[]` | 参数数组，逐项原样传递（无需自己加引号） |
| `cwd` | string | exe 所在目录 | 工作目录 |
| `env` | object\<string,string\> | `{}` | 追加 / 覆盖子进程环境变量 |
| `match` | object | `{}` | 窗口识别规则；写的字段之间是 **AND** 关系，未写的字段不参与匹配 |
| `match.exe` | string | 无 | 进程文件名（不区分大小写） |
| `match.path` | string | 无 | 进程完整路径通配（`*`、`?`） |
| `match.class` | string | 无 | 窗口类名（精确匹配） |
| `match.title` | string | 无 | 窗口标题正则（`std.regex`） |
| `startupWaitMs` | number | `8000` | 启动后等待窗口出现的上限；超时记 warn 并继续 |
| `reuse` | 枚举：existing、new | `"existing"` | `existing`：已有匹配窗口则直接收编，不再新开进程 |
| `maximizeOnStart` | bool | `false` | 窗口出现后先最大化，再参与组布局 |

**launches**（键 `<launchId>` 为 kebab-case 字符串）

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `apps` | array\<appId\> | 无（集合内**必填**） | 按顺序启动；引用不存在的 appId → E2001 |
| `staggerMs` | number | `300` | 相邻两次启动的间隔（毫秒） |
| `group` | string 或 null | `null` | 启动后把命中的窗口收编进该组 |
| `layout` | string 或 null | `null` | 收编后应用的布局（覆盖组自带布局） |

**layouts**（键 `<layoutId>` 为 kebab-case 字符串）

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `type` | 枚举：grid、ratio、absolute、anchor | `"grid"` | 布局算法 |
| `columns` / `rows` | number | `1` / `1` | `grid`：网格列数与行数 |
| `gap` | number | `8` | 格子之间的间隙（像素） |
| `margins` | array\[4\] number | `[0,0,0,0]` | 工作区外边距，顺序为 左、上、右、下 |
| `ratios` | array\<number\> | 无 | `ratio`：各栏宽度占比，元素个数 = 栏数，之和应为 1.0（否则 E2007） |
| `cells` | array\<array\[4\] number\> | 无 | `absolute`：每格 `[left, top, right, bottom]`，取值是**百分比**（0~100） |
| `monitor` | primary、secondary 或 0 起的索引 | `"primary"` | 目标显示器 |
| `order` | 枚举：listed、zorder、title | `"listed"` | 窗口与格子的对应顺序 |
| `anchor` | 枚举：left、right、top、bottom、top-left、top-right、bottom-left、bottom-right、center | `"center"` | `anchor`：贴靠位置 |
| `size` | array\[2\] string | `["50%","50%"]` | `anchor`：宽高（百分比或像素，如 `"800"`） |

**groups**（键 `<groupId>` 为 kebab-case 字符串）

| 键 | 类型 | 默认 | 说明 |
| --- | --- | --- | --- |
| `name` | string | 取 groupId | 显示名 |
| `layout` | string | `behavior.defaultLayout` | 组的布局；引用不存在 → E2001 |
| `apps` | array\<appId\> | `[]` | 声明式成员：匹配到这些应用的新窗口自动收编 |
| `monitor` | 同 `layouts.monitor` | `"primary"` | 组的目标显示器 |
| `activate` | 枚举：focus-last、focus-first、cycle | `"focus-last"` | 激活组时的聚焦策略 |
| `onSwitchAway` | 枚举：minimize、hide、keep | `"minimize"` | 切走时旧组窗口的处理 |
| `onActivate` | 枚举：restore、keep-size | `"restore"` | 切回时是否恢复被最小化 / 隐藏的窗口 |

### 7.5 完整示例（`config/winun.json`）

```json
{
  "$schema": "./winun.schema.json",
  "version": 1,
  "$comment": "winun v1 配置示例。JSON 不支持注释，说明文字统一写在 $comment 键里（解析时忽略）。",
  "log": {
    "level": "debug",
    "file": "%APPDATA%\\winun\\logs\\winun.log",
    "rotateKb": 2048
  },
  "behavior": {
    "watchConfig": true,
    "startupGroup": "coding",
    "defaultLayout": "two-columns",
    "commandTimeoutMs": 150,
    "strict": false
  },
  "hotkeys": {
    "win+alt+1": "launch dev-env",
    "win+alt+2": "launch meeting",
    "win+alt+3": "group activate browser",
    "win+alt+4": "layout apply quad",
    "win+alt+tab": "group cycle next",
    "win+alt+shift+tab": "group cycle prev",
    "win+alt+q": "window to-group current",
    "win+alt+w": "window remove-from-group",
    "win+alt+r": "layout apply current",
    "win+alt+left": "window snap left-half",
    "win+alt+right": "window snap right-half",
    "win+alt+up": "window snap maximize",
    "win+alt+down": "window snap restore",
    "win+alt+f": "window float toggle",
    "win+alt+shift+r": "config reload",
    "win+alt+shift+q": "quit"
  },
  "apps": {
    "vscode": {
      "exe": "%LOCALAPPDATA%\\Programs\\Microsoft VS Code\\Code.exe",
      "args": [],
      "cwd": "%USERPROFILE%\\workspace",
      "env": {
        "VSCODE_LOG_LEVEL": "info"
      },
      "match": {
        "exe": "Code.exe",
        "title": ".*- Visual Studio Code"
      },
      "startupWaitMs": 10000,
      "reuse": "existing",
      "maximizeOnStart": false
    },
    "terminal": {
      "exe": "wt.exe",
      "args": [
        "-p",
        "Ubuntu"
      ],
      "cwd": "%USERPROFILE%",
      "match": {
        "exe": "WindowsTerminal.exe"
      },
      "startupWaitMs": 6000,
      "reuse": "existing",
      "maximizeOnStart": false
    },
    "chrome": {
      "exe": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
      "args": [
        "--profile-directory=Default"
      ],
      "match": {
        "exe": "chrome.exe",
        "class": "Chrome_WidgetWin_1"
      },
      "startupWaitMs": 8000,
      "reuse": "existing",
      "maximizeOnStart": false
    },
    "meeting": {
      "exe": "C:\\Program Files\\Tencent\\WeMeet\\wemeetapp.exe",
      "args": [],
      "match": {
        "exe": "wemeetapp.exe"
      },
      "startupWaitMs": 15000,
      "reuse": "new",
      "maximizeOnStart": true
    }
  },
  "launches": {
    "dev-env": {
      "apps": [
        "vscode",
        "terminal",
        "chrome"
      ],
      "staggerMs": 300,
      "group": "coding",
      "layout": "main-side"
    },
    "meeting": {
      "apps": [
        "meeting"
      ],
      "staggerMs": 0,
      "group": "meeting",
      "layout": "meeting"
    }
  },
  "layouts": {
    "two-columns": {
      "type": "grid",
      "columns": 2,
      "rows": 1,
      "gap": 8,
      "margins": [
        8,
        8,
        8,
        8
      ],
      "monitor": "primary",
      "order": "listed"
    },
    "main-side": {
      "type": "ratio",
      "ratios": [
        0.7,
        0.3
      ],
      "gap": 8,
      "margins": [
        8,
        8,
        8,
        8
      ],
      "monitor": "primary"
    },
    "meeting": {
      "type": "anchor",
      "anchor": "center",
      "size": [
        "90%",
        "90%"
      ],
      "monitor": "primary"
    },
    "quad": {
      "type": "absolute",
      "cells": [
        [
          0,
          0,
          50,
          50
        ],
        [
          50,
          0,
          100,
          50
        ],
        [
          0,
          50,
          50,
          100
        ],
        [
          50,
          50,
          100,
          100
        ]
      ],
      "monitor": "secondary",
      "order": "listed"
    }
  },
  "groups": {
    "coding": {
      "name": "编码组",
      "layout": "main-side",
      "apps": [
        "vscode",
        "terminal"
      ],
      "monitor": "primary",
      "activate": "focus-last",
      "onSwitchAway": "minimize",
      "onActivate": "restore"
    },
    "browser": {
      "name": "浏览组",
      "layout": "two-columns",
      "apps": [
        "chrome"
      ],
      "monitor": "primary",
      "activate": "focus-first",
      "onSwitchAway": "hide",
      "onActivate": "restore"
    },
    "meeting": {
      "name": "会议组",
      "layout": "meeting",
      "apps": [
        "meeting"
      ],
      "monitor": "primary",
      "activate": "focus-first",
      "onSwitchAway": "minimize",
      "onActivate": "restore"
    }
  }
}
```

约定：顶层 `id` 键（apps / launches / layouts / groups）一律 kebab-case；`version` 必须为 `1`；所有被引用的 appId / layoutId / groupId 必须存在；字符串统一 UTF-8（中文组名、中文路径均可）。

### 7.6 校验与错误处理

| 前缀 | 类别 | 典型错误 |
| --- | --- | --- |
| E100x | JSON 语法 / 类型错误（解析期，**必须带 file:line:column**） | E1001 文件不存在或无法读取；E1002 语法错误；E1003 同一对象内重复键；E1004 类型不符（期望 number，实际 string）；E1005 非法转义或非法 UTF-8 |
| E200x | 语义错误（校验期） | E2001 引用不存在的 layout / group / app；E2002 重复的热键绑定；E2003 非法组合键（未知键名、只有修饰键）；E2004 `version` 不是 1；E2005 未知键（仅 `strict` 模式）；E2006 动作参数非法（如 `group cycle` 缺 next / prev）；E2007 `ratios` 之和不为 1.0 |
| E300x | 运行时错误 | E3001 热键注册失败（已被占用）；E3002 Win32 调用失败；E3003 被启动应用超时未出现窗口 |

- 输出格式（一律带 **file:line:column**）：`winun.json:42:17: E2001 引用不存在的布局 "main-sdie"（是否想写 "main-side"？）`
- `winun validate --config <file\|dir>`：只解析与校验，不注册热键、不操作窗口；`--json` 输出机器可读的错误列表。
- 退出码：`0` 成功；`2` 配置错误（E100x / E200x）；`3` 热键全部注册失败；`4` 平台调用失败；`5` 已有实例在运行。

### 7.7 JSON Schema

- 仓库随附 `config/winun.schema.json`（JSON Schema draft 2020-12），供 VS Code / JetBrains 等编辑器补全与内联校验；配置里可用 `"$schema": "./winun.schema.json"` 指向它（以 `$` 开头的键会被 winun 忽略）。
- Schema 要点：
  - 头部：`"$schema": "https://json-schema.org/draft/2020-12/schema"`、`"title": "winun config"`、`"type": "object"`；
  - 必需与常量：`"required": ["version"]`、`"properties": { "version": { "const": 1 } }`；
  - 枚举：`log.level`、`layouts.*.type`、`layouts.*.order`、`layouts.*.anchor`、`apps.*.reuse`、`groups.*.activate`、`groups.*.onSwitchAway`、`groups.*.onActivate` 全部用 `"enum"` 列全；
  - 数值与数组约束：`"minimum"` / `"maximum"`（如 `ratios` 元素 0~1、`gap >= 0`）、`"minItems": 4, "maxItems": 4`（`margins`）、`"items": { "type": "number" }`（`cells` 的行）；
  - 动态键：`apps` / `launches` / `layouts` / `groups` 用 `"additionalProperties": { "$ref": "#/$defs/app" }` 描述；`hotkeys` 用 `"patternProperties": { "^[a-z0-9+]+$": { "type": "string" } }`；
  - 定义复用：`$defs` 中抽出 `monitor`、`appId`、`layoutId`、`groupId`、`rect`，供 `layouts.monitor` 与 `groups.monitor` 共用；
  - `"additionalProperties": false` 只开在 `$defs` 的叶子对象上（与 `strict` 语义对齐），顶层保持开放以兼容 `$comment` / `$schema`。
- Schema 与运行时校验**同源**：v1 只要求两者语义一致，不强制由 Schema 生成代码；CI 中用同一份"合法 / 非法样本集"同时喂给 `winun validate` 与 Schema 校验器（M1 起）。

### 7.8 热重载

1. 每 1 s 轮询 `winun.json`（以及存在时的 `winun.user.json`）的大小 + 修改时间（`std.fs`），或用 `ReadDirectoryChangesW`（P2）。
2. 变更 → 在 T1 解析为新的 `ConfigSnapshot`（含 `winun.user.json` 深合并、环境变量展开、语义校验）。
3. 与旧快照 diff：热键集合变化 → 注销旧、注册新；组 / 布局变化 → 更新 Registry 与 Session；应用定义变化 → 仅影响下次启动；`log.*` 变化 → 切换日志级别。
4. 解析 / 校验失败 → **回滚到旧快照**并记 error 日志（常驻服务不因配置错误而中断），日志与错误信息中给出 `file:line:column`。

---

## 8. Windows 平台适配层（`winun.win32`）

### 8.1 API 清单

| 分组 | API | 用途 | 优先级 |
| --- | --- | --- | --- |
| 热键 | `RegisterHotKey`, `UnregisterHotKey`, `GetMessageW`, `TranslateMessage`, `DispatchMessageW`, `PostThreadMessageW`, `PostQuitMessage` | 热键注册与消息循环 | P0 |
| 窗口枚举 | `EnumWindows`, `IsWindowVisible`, `IsWindow`, `GetWindow`, `GetAncestor`, `GetWindowLongPtrW` | 建立窗口清单、过滤工具窗口 | P0 |
| 窗口信息 | `GetWindowTextLengthW`, `GetWindowTextW`, `GetClassNameW`, `GetWindowRect`, `IsIconic`, `IsZoomed`, `GetForegroundWindow` | WindowInfo 快照 | P0 |
| 窗口操作 | `SetWindowPos`, `ShowWindow`, `MoveWindow`, `SetForegroundWindow`, `BringWindowToTop`, `ShowWindowAsync` | 布局执行与聚焦 | P0 |
| 进程识别 | `GetWindowThreadProcessId`, `OpenProcess`, `QueryFullProcessImageNameW`, `CloseHandle`, `WaitForInputIdle` | AppId 识别、启动等待 | P0 |
| 进程启动 | `CreateProcessW`, `GetEnvironmentStringsW`, `SetEnvironmentVariableW`（或自组环境块） | 启动应用 | P0 |
| 显示器 | `MonitorFromWindow`, `GetMonitorInfoW`, `EnumDisplayMonitors`, `GetDpiForWindow`, `SetProcessDpiAwarenessContext` | 工作区与 DPI | P1 |
| DWM | `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` | 修正"可见边框"与 `GetWindowRect` 的差异 | P1 |
| 事件 | `SetWinEventHook`, `UnhookWinEvent`（`EVENT_OBJECT_CREATE/DESTROY/NAMECHANGE/FOREGROUND`） | 窗口出现/消失自动收编 | P1 |
| 单实例/集成 | `CreateMutexW`, `GetLastError`, `GetModuleHandleW`, `RegisterWindowMessageW` | 单实例、错误码 | P2 |
| 托盘（后置） | `Shell_NotifyIconW`, `LoadIconW`, `CreatePopupMenu`, `TrackPopupMenu` | 托盘菜单 | P2 |

### 8.2 FFI 声明与封装（示意）

    package winun.win32

    public type HWND = CPointer<Unit>

    let SWP_NOZORDER: UInt32 = 0x0004
    let SWP_NOACTIVATE: UInt32 = 0x0010
    let SWP_SHOWWINDOW: UInt32 = 0x0040

    @CallingConv[STDCALL]
    foreign func SetWindowPos(hWnd: HWND, after: HWND, x: Int32, y: Int32,
                              cx: Int32, cy: Int32, flags: UInt32): Bool

    // 安全封装：对外只暴露领域类型，unsafe 不越层
    public func placeWindow(id: WindowId, rect: Rect, activate: Bool): Bool {
        let flags = SWP_NOZORDER | (if (activate) { 0 } else { SWP_NOACTIVATE })
        return unsafe {
            SetWindowPos(id.toHwnd(), HWND(), rect.left, rect.top,
                         rect.right - rect.left, rect.bottom - rect.top, flags)
        }
    }

要点：

- 每个 API 返回 `Bool`（失败）时立即取 `GetLastError()`，转换为 `Win32Error(code, api, message)`。
- 句柄包装为 `WindowId(UInt64)` 在领域层流转，只在 `winun.win32` 内部还原为 `HWND`。
- 所有结构体在 `win32` 包内定义，并提供 `abi_check()`：用 `sizeOf<T>()` 与预期值比对（单测中执行）。

### 8.3 回调桥接

仓颉的 `CFunc` **不能捕获变量**，回调必须是顶层非泛型函数，因此：

    package winun.win32

    import std.sync.*
    import std.collection.concurrent.*

    let eventQueue = ConcurrentLinkedQueue<WindowEvent>()
    var gHookCtx: Int64 = 0

    // 顶层 @C 函数：枚举回调
    @C
    @CallingConv[STDCALL]
    func enumWindowsProc(hwnd: HWND, lParam: Int64): Bool {
        if (isCandidateWindow(hwnd)) {
            eventQueue.add(WindowEvent.Found(toId(hwnd)))
        }
        return true // 继续枚举
    }

    // 事件钩子回调：只入队，不做业务
    @C
    @CallingConv[STDCALL]
    func winEventProc(hook: Handle, event: UInt32, hwnd: HWND,
                      idObject: Int32, idChild: Int32, thread: UInt32, time: UInt32): Unit {
        eventQueue.add(WindowEvent.Raw(event, toId(hwnd)))
    }

约束与注意事项：

- 回调里禁止做文件 IO、配置解析、布局计算等重活；只入队。
- 回调可能在任意线程被调用（`SetWinEventHook` 回调在注册线程的消息循环中被派发，`EnumWindows` 在当前线程），因此共享状态一律用 `Mutex` 或并发容器。
- 需要在回调中传递业务上下文时，使用顶层全局变量（必要时用 `Mutex` 保护），不要试图用闭包。

### 8.4 消息循环与唤醒

    // 主线程伪流程
    let tid = unsafe { GetCurrentThreadId() }
    registerHotkeys(bindings, tid)          // 全部热键在此线程注册
    startWorkerThreads(tid)                 // 传入 tid 以便 PostThreadMessageW 唤醒
    var msg = MSG()
    while (unsafe { GetMessageW(inout msg, HWND(), 0, 0) }) {
        match (msg.message) {
            case WM_HOTKEY => handleHotkey(Int32(msg.wParam))
            case WM_APP + 1 => drainCommandQueue()      // 工作线程投递的命令
            case _ => unsafe { TranslateMessage(inout msg); DispatchMessageW(inout msg) }
        }
    }

- `WM_HOTKEY = 0x0312`、`WM_APP = 0x8000`。
- 工作线程投递窗口操作命令后，必须 `PostThreadMessageW(tid, WM_APP + 1, 0, 0)`，否则 `GetMessageW` 不会被唤醒。

### 8.5 字符串与结构体 ABI

- 统一使用 W 系列 API，字符串以 UTF-16LE 传入：
  - 领域层 `String`（UTF-8）→ `Array<UInt16>`（含结尾 0）→ `CPointer<UInt16>`。
  - 读取时反向转换，长度由 API 返回或先探测。
  - 转换函数放在 `winun.infra.text`（`toUtf16(s: String): Array<UInt16>`、`fromUtf16(p: CPointer<UInt16>, len: Int32): String`），并配中文往返单测。
- 结构体使用 `@C struct`；字段顺序、类型宽度、对齐必须与 C 头文件一致：
  - `POINT`(8) / `RECT`(16) / `MSG`(48 on x64) / `WINDOWPLACEMENT`(44) / `MONITORINFO`(40) / `STARTUPINFOW`(104) / `PROCESS_INFORMATION`(24)。
  - 在单测中通过 `sizeOf<T>()` 断言上述尺寸，尺寸不符立即失败，避免"能编译但内存错位"的隐蔽 bug。
- 需要保留字段（如 `PAINTSTRUCT.rgbReserved`）用 `VArray<Byte, $32>` 占位。

---

## 9. 关键流程

### 9.1 启动

    winun.exe [--config DIR] [--console] [--log-level LVL]
      │
      ├─ 解析 CLI → 定位配置目录
      ├─ 单实例检查：CreateMutexW("Global\\winun") → 已存在则退出码 5
      ├─ 解析 winun.json（存在 winun.user.json 时先深合并）→ ConfigSnapshot
      │   （失败 → 打印 file:line:column + 退出码 2）
      ├─ 初始化日志（文件 + 可选控制台）
      ├─ 构建 Registry：枚举窗口 → 识别 AppId → 归入组
      ├─ 注册热键（逐条记录成功/冲突）
      ├─ 启动工作线程（事件消费、热重载、启动等待）
      ├─ 若有 startupGroup → 执行一次组激活
      └─ 进入 GetMessageW 循环（T0）

### 9.2 一键启动应用并收编窗口

    热键 launch dev-env
      → T0: 查配置，得到 [vscode, terminal, chrome]
      → T0 → T1: 投递 LaunchCommand
      → T1: 依次 CreateProcessW（间隔 `staggerMs`）
            对每个应用：轮询 EnumWindows + `match.exe`/`match.title` 命中窗口
                        （上限 `startupWaitMs`，超时记 warn 并继续）
            命中的窗口 → 加入目标组（group = coding）
      → T1 → T0: 投递 ApplyLayoutCommand
      → T0: layout.solve(...) → placeBatch(...) → 记录 Placement 快照

- "已存在实例"（`reuse: "existing"`）时先枚举匹配窗口，命中则直接收编，不再新开进程。

### 9.3 组切换

    热键 group cycle next
      → 计算下一组（按 `winun.json` 中 `groups` 的声明顺序，循环）
      → 旧组：按 `onSwitchAway` 处理（minimize / hide / keep）
      → 新组：ShowWindow(SW_RESTORE) 恢复（若被最小化/隐藏）
      → 对新组执行布局（layout.solve + placeBatch）
      → 聚焦策略：focus-last（记录每组上一次的前台窗口）/
                   focus-first（组内第一个窗口）/
                   cycle（组内轮转）
      → 保存 Session 状态：activeGroup = 新组

前台聚焦失败的处理顺序：`SetForegroundWindow` → 失败则 `AllowSetForegroundWindow(ASFW_ANY)` 后重试 → 仍失败则 `AttachThreadInput` 到目标线程再重试（P1 实现，v0.1 只记录日志）。

### 9.4 单窗口布局

    热键 window snap left-half
      → 取前台窗口 → 查其所在显示器工作区
      → 用内置的 anchor 布局解算（50% 宽 × 100% 高，贴左）
      → SetWindowPos(SWP_NOZORDER | SWP_NOACTIVATE)  // 不抢焦点

### 9.5 热重载

    `winun.json` 的 mtime 变化 → T1 解析 → diff：
      热键集合变化 → 投递到 T0 重新注册（先撤销全部再注册，避免残留）
      组/布局变化   → 更新 Registry 与 ConfigSnapshot
      应用定义变化 → 仅下次启动生效
    解析失败 → 保留旧快照 + error 日志

---

## 10. 窗口组合（Grouping）方案选型

Windows 没有"进程无关的窗口分组"这一原生语义，必须自建。三种可选路线：

| 方案 | 做法 | 优点 | 风险 | 结论 |
| --- | --- | --- | --- | --- |
| A 虚拟组（批量显隐 + 布局） | 记录组内 HWND 集合，切换时批量 `ShowWindow`/`SetWindowPos` | 零侵入、实现简单、可随时回滚、不改变窗口父子关系 | 窗口仍在任务栏/Alt+Tab 中出现（可用 `ITaskbarList`/`WS_EX_TOOLWINDOW` 优化，属 P2）；被其他工具移动后不自动归位 | **v0.1 采用** |
| B 容器窗口（`SetParent`） | 建一个宿主窗口，把组内窗口 `SetParent` 进去，像"标签页" | 视觉上真成一个整体，可整体移动/最小化 | 跨进程 `SetParent` 引发输入法、DPI、焦点、最小化动画异常；应用自绘/GPU 渲染窗口易出错；崩溃风险高 | v0.4 之后评估，需 C shim |
| C 虚拟桌面 / 未公开 COM | 用 `IVirtualDesktopManager` 或虚拟桌面 COM 接口 | 与系统语义一致，任务栏天然隔离 | 接口未公开、随 Windows 版本变动；COM 调用需手工 vtable，仓颉 FFI 成本高 | 明确后置，先只做"只读查询"（判断窗口是否在当前桌面） |

**抽象保留**：定义 `WindowCompositor` 接口（`attach`/`detach`/`activateGroup`/`deactivateGroup`），v0.1 由 `VirtualGroupCompositor` 实现；将来方案 B/C 只需新增实现，不改上层。

---

## 11. 错误处理、日志与可观测性

- 错误类型分层：`ConfigError`（带文件名/行号）、`Win32Error`（api + code + 文本）、`DomainError`。
- 统一策略：**配置错误阻断启动**；**运行时窗口操作错误降级为日志**（不中断常驻服务）。
- 日志：`%APPDATA%\winun\logs\winun.log`，格式 `2026-01-01 12:00:00.123 [INFO] [core.dispatcher] group=coding action=ApplyLayout windows=3 cost=42ms`。
- 诊断命令：
  - `winun list windows`：打印当前所有候选窗口（HWND/PID/进程/类名/标题/矩形/显示器）。
  - `winun list groups`：打印组与成员（含"未命中成员"提示）。
  - `winun list hotkeys`：打印已注册热键与冲突项。
  - `winun doctor`：检查 DPI 感知、管理员权限、配置路径可写性、与已知冲突软件（如输入法/游戏加速器）的提示。
- `--console`：`AllocConsole` 或直接以控制台程序运行（M0 验证 S-8）。

---

## 12. 构建、运行与发布

    # 环境（PowerShell）
    . <cangjie-sdk>\envsetup.ps1
    cjc -v

    # 构建与运行
    cjpm build                 # 产物：target/release/bin/winun.exe
    cjpm run --run-args "--config .\config --console"
    cjpm test                  # 运行 *_test.cj

    # 安装（脚本）
    scripts\install.ps1        # 复制到 %LOCALAPPDATA%\winun，写开机自启（HKCU\...\Run）

- 版本号：`MAJOR.MINOR.PATCH`，与 `cjpm.toml`/`cjc-version` 同步维护；`winun --version` 输出编译器版本与自身版本。
- 发布物：`winun-<ver>-win-x64.zip`（winun.exe + `config\winun.json` + `config\winun.schema.json` + README）。
- 依赖策略：v0.1 仅标准库（零 `stdx` 依赖），降低版本耦合与分发成本。

---

## 13. 测试策略

| 层次 | 对象 | 手段 |
| --- | --- | --- |
| 单元测试（无平台依赖） | JSON 词法/语法（含行列号定位）、字段映射与默认值、类型校验、深合并、Chord 解析、布局解算、AppId 匹配 | `std.unittest`（`*_test.cj`）+ 表驱动用例 |
| ABI 测试 | `@C struct` 尺寸与字段偏移 | `sizeOf<T>()` 断言 |
| 编码测试 | UTF-8 ↔ UTF-16 往返（含中文、emoji 代理对） | 单元测试 |
| 集成测试（需 Windows 会话） | 热键注册、窗口枚举、SetWindowPos、进程启动 | 手工脚本 + 测试用假目标程序（如启动 `notepad.exe`） |
| 回归场景 | 组切换、热重载、冲突热键、被管理员窗口拒绝操作 | 手工清单（M2 起写成 `docs/testing.md` 的检查表） |
| 模糊/健壮性 | 畸形 JSON（非法转义、重复键、深嵌套、截断文件、超长字符串） | 单元测试喂样本文件 |

设计上的可测性保障：布局、解析、匹配全部为纯函数；平台能力全部藏于 trait 之后，测试时注入 `Null*` 实现或伪造的 `FakeWindowBackend`。

---

## 14. 里程碑

| 里程碑 | 内容 | 验收标准 | 预估 |
| --- | --- | --- | --- |
| **M0 技术验证** | 环境 + S-1..S-10 十个 spike + `spike/` demo | 热键触发 → 前台窗口移动到右半屏；配置读取含中文正常；无控制台运行 | 1~2 周 |
| **M1 骨架** | 目录与包结构、`infra`（日志/文本/错误）、`config` 解析与校验、`cli`（validate/version/list）、单实例 | `winun validate` 对示例 `winun.json` 给出 0 错误；错误配置给出精确 file:line:column 与退出码 2 | 2 周 |
| **M2 核心功能** | 热键注册、应用启动与窗口收编、布局引擎、组模型与切换、`--dry-run` | US-1/US-3/US-4 全流程可用；`Win+Alt+1` 从零到布局完成 < 15 s（含应用启动） | 3~4 周 |
| **M3 完善** | 多显示器与 DPI、窗口事件监听、热重载、doctor、安装脚本与自启 | US-5 生效；双屏环境下布局正确；配置改错不影响常驻 | 2 周 |
| **M4 增强（持续）** | 托盘菜单、`ITaskbarList` 隔离、方案 B/C 评估、shim 化、图形配置器 | 按需排期 | — |

---

## 15. 风险与对策

| 编号 | 风险 | 概率 | 影响 | 对策 |
| --- | --- | --- | --- | --- |
| R-1 | Windows 仓颉后端（MinGW）功能欠缺导致链接/调试受阻 | 中 | 高 | M0 优先验证 S-2/S-8；失败则引入 `native/` C shim 并走 `[ffi.c]` |
| R-2 | `CFunc` 不能捕获变量导致回调上下文难管理 | 高 | 中 | 全局单例上下文 + 队列；回调只入队 |
| R-3 | 前台锁定规则导致聚焦失败 | 中 | 中 | `AllowSetForegroundWindow`/`AttachThreadInput` 兜底；失败仅记日志 |
| R-4 | UIPI：无法操作管理员权限窗口 | 高 | 中 | 明确日志 + 文档提示；提供"以管理员运行"选项 |
| R-5 | 结构体 ABI 不一致导致内存错位 | 中 | 高 | `sizeOf` 断言单测 + 只用文档化字段 |
| R-6 | 多显示器/DPI 缩放导致布局偏移 | 高 | 中 | Per-Monitor V2；用 `DWMWA_EXTENDED_FRAME_BOUNDS`；按显示器工作区解算 |
| R-7 | 配置格式与语义反复变更 | 中 | 低 | 版本字段 + 校验 + 向后兼容的"未知键警告"策略 |
| R-8 | stdx 依赖的跨版本不兼容 | 中 | 中 | v0.1 零 stdx 依赖 |
| R-9 | 仓颉语言/工具链版本升级带来破坏性变更 | 中 | 中 | `cjpm.toml` 锁定 `cjc-version`；`cjpm.lock` 入库 |
| R-10 | 与第三方窗口工具（输入法、游戏加速器、其他 WM）冲突 | 中 | 低 | `doctor` 检测与提示；操作幂等、失败可重试 |

---

## 16. 待决问题（Open Questions）

| 编号 | 问题 | 当前倾向 | 决策时点 |
| --- | --- | --- | --- |
| Q-1 | 是否额外支持 TOML / YAML 配置 | 已决定用 JSON（v1 规范冻结）；额外格式后置到 M4 | M4 |
| Q-2 | 旧组窗口的默认处理（minimize / hide） | 默认 `minimize`（对任务栏更友好） | M2 |
| Q-3 | 是否需要托盘与图形配置界面 | v0.1 不做；M4 评估托盘 + HTML 配置器 | M3 |
| Q-4 | 是否引入虚拟桌面（COM）能力 | 后置；先只做只读判断 | M4 |
| Q-5 | 是否引入 `native/` C shim | 仅在 M0 spike 失败或引入钩子/COM 时启用 | M0 结束 |
| Q-6 | 是否需要多用户/多会话支持（RDP 场景） | 暂不支持，单会话假设 | 待定 |
| Q-7 | 布局溢出策略（窗口数 > 格子数） | 堆叠到最后一格并偏移，或自动扩展行数 | M2 |

---

## 附录 A：常用 Win32 常量

| 名称 | 值 | 说明 |
| --- | --- | --- |
| `WM_HOTKEY` | 0x0312 | 热键消息 |
| `WM_APP` | 0x8000 | 自定义消息起点 |
| `MOD_ALT/CONTROL/SHIFT/WIN` | 0x1/0x2/0x4/0x8 | 热键修饰键 |
| `MOD_NOREPEAT` | 0x4000 | 抑制长按重复触发 |
| `SWP_NOZORDER` | 0x0004 | 不改 Z 序 |
| `SWP_NOACTIVATE` | 0x0010 | 不激活窗口 |
| `SWP_SHOWWINDOW` | 0x0040 | 顺带显示 |
| `SW_MINIMIZE / SW_RESTORE / SW_HIDE / SW_SHOWNOACTIVATE` | 6 / 9 / 0 / 4 | `ShowWindow` 命令 |
| `GWL_EXSTYLE` / `WS_EX_TOOLWINDOW` | -20 / 0x00000080 | 过滤工具窗口 |
| `DWMWA_EXTENDED_FRAME_BOUNDS` | 9 | DWM 真实可见边界 |
| `ERROR_HOTKEY_ALREADY_REGISTERED` | 1409 | 热键被占用 |
| `ASFW_ANY` | -1 | `AllowSetForegroundWindow` 参数 |

## 附录 B：按键名映射

| 类别 | 可写名 | 说明 |
| --- | --- | --- |
| 字母数字 | `a`..`z`, `0`..`9` | 映射到 VK 码 |
| 功能键 | `f1`..`f24` | |
| 方向 | `left`, `right`, `up`, `down` | |
| 导航 | `home`, `end`, `pgup`, `pgdn`, `insert`, `delete` | |
| 编辑 | `enter`, `esc`, `tab`, `space`, `backspace` | |
| 符号 | `-`, `=`, `[`, `]`, `;`, `'`, `,`, `.`, `/`, `\`（反斜杠） | 需按物理键位映射 |
| 修饰 | `win`, `ctrl`, `alt`, `shift` | 仅作为修饰键，不单独作主键 |

## 附录 C：参考资料

- 仓颉用户手册 · 仓颉-C 互操作：https://docs.cangjie-lang.cn/en/docs/1.0.0/user_manual/source_zh_cn/FFI/cangjie-c.html
- 仓颉用户手册 · 安装仓颉工具链（含 Windows / MinGW 说明）：https://docs.cangjie-lang.cn/docs/1.0.4/user_manual/source_zh_cn/first_understanding/install_Community.html
- cjpm 工具手册（`cjpm.toml`、`[ffi.c]`、`link-option`、`target`）：https://gitcode.com/Cangjie/cangjie_docs/blob/main/docs/tools/source_zh_cn/cmd-tools/cjpm_manual.md
- 仓颉官方示例 · 基于 CFFI 的 Windows GUI 编程（`foreign func` + `@C` + `STDCALL` + `link-option`）：https://gitcode.com/Cangjie/Cangjie-Examples/tree/main/CFFI-Windows
- 仓颉扩展库 stdx（JSON/日志等，支持 windows-x64）：https://gitcode.com/Cangjie/cangjie_stdx
- Microsoft Learn · RegisterHotKey / SetWindowPos / SetWinEventHook / CreateProcessW 等 Win32 API 文档：https://learn.microsoft.com/windows/win32/

---

> 下一步（建议）：先执行 M0 的 S-2/S-3/S-4 三项 spike（FFI 链接 → 热键闭环 → 窗口操作），把 demo 跑通后再落地第 5 章的目录结构；同时把第 7 章的配置规范冻结为 `docs/config-reference.md` v1。
