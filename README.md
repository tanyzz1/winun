# winun

> 用 **仓颉语言（Cangjie）** 编写的 Windows 配置驱动窗口管理器：全局快捷键启动应用、按布局摆放窗口、把窗口编成「组」并一键切换。

当前状态：**M1 骨架已落地**——`cjpm build` 通过、27 个单元测试通过、示例配置 `validate` 通过；配置格式为 **JSON**（设计文档 v0.2）。

## 文档

- [winun 初期设计文档 v0.2](docs/winun-初期设计文档.md) —— 定位、架构分层、目录结构、领域模型、JSON 配置规范（第 7 章）、Win32 FFI 方案、里程碑与风险
- [M0 技术验证报告](docs/spike-report.md) —— 在真实 Windows + 仓颉 1.0.5 上验证到的能力、踩到的坑与结论

## 目标能力

| 能力 | 说明 |
| --- | --- |
| 快捷键启动 | 一组快捷键按配置拉起整套应用（编辑器 + 终端 + 浏览器） |
| 布局管理 | 网格 / 比例 / 绝对坐标 / 贴边（anchor）/ 溢出堆叠 |
| 窗口分组 | 把若干窗口编成一个「组」，组内共享一套布局 |
| 快捷键切换 | 组之间循环切换、把当前窗口收进/移出组、焦点策略 |
| 配置驱动 | 全部行为来自 `config/winun.json`，支持热重载 |

## 快速开始

```powershell
# 1. 准备仓颉工具链（Windows x64）
. "C:\Program Files (x86)\Cangjie\envsetup.ps1"
cjc -v            # Cangjie Compiler: 1.0.5 (cjnative)

# 2. 构建与测试
cjpm build        # 产物：target/release/bin/main.exe
cjpm test         # 36 个单元测试：JSON / UTF-8 边界 / 组合键 / 动作 / 布局 / 配置校验 / 编排（记录型后端）
.\target\release\bin\main.exe selftest
#   -> 16 项平台自检：ABI 断言 + 自建窗口的真实布局执行闭环 + 热键注册探测（沙箱内也能跑）

# 3. 校验配置（示例配置在 config/winun.json）
.\target\release\bin\main.exe validate --config config\winun.json
#   -> 配置有效：apps=5 launches=3 layouts=5 groups=3 hotkeys=14

# 4. 列出当前可见窗口（真实枚举 Win32 顶层窗口，并标出匹配到的应用）
.\target\release\bin\main.exe list windows
#   -> 只列出真实应用窗口（已过滤 Shell_TrayWnd/DummyDWMListenerWindow 等外壳噪声）
#      最后一列「匹配应用」告诉你该窗口会被收编进哪个 app（例如 msedge.exe -> edge）

# 5. 常驻运行（注册全局热键并等待；--console 同时打印日志）
.\target\release\bin\main.exe run --config config\winun.json --console
#   默认热键：win+alt+f1 启动 dev-env、f3 切到 browser 组、f4/q 组间轮转、f8/f9 左右半屏…
```

> **热键冲突**：组合键能否使用取决于本机其它程序。运行
> `main.exe selftest --config config\winun.json` 会逐条探测配置里的组合键（探测前请先退出正在运行的 winun）。
> 本机实测 win+alt+1/2/3/tab/w/r/方向键 已被其它软件占用，因此示例配置默认使用 win+alt+f1..f12 / q / e / z。
>
> **配置里的应用路径是本机实际的**（VS Code 在 `D:\Microsoft VS Code`、Firefox Nightly 在 `D:\Firefox Nightly`、
> Edge / WPS / Windows Terminal / 记事本等）。换机器时用「注册表 App Paths + Get-Command + 运行中进程」三板斧找真实路径：
> ```powershell
> Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths' |
>   ForEach-Object { $v=(Get-ItemProperty $_.PSPath).'(default)'; if($v){ $_.PSChildName + ' => ' + $v } }
> ```
> 改完路径后用 `main.exe list windows` 看「匹配应用」列确认匹配规则是否命中。
>
> **`cjpm test` 在受限环境下可能报 worker/临时文件失败**（仓颉 unittest 框架要拉起并行 worker 进程）：
> 先编译再逐个跑测试二进制即可绕过——
> ```powershell
> cjpm test --no-run
> cd target\release\unittest_bin
> foreach ($p in 'winun.infra','winun.domain','winun.layout','winun.config','winun.core') { & ".\$p.exe" }
> ```
>
> **重新编译前请先退出正在运行的 winun**：否则 main.exe 被占用，链接会报 ld.lld: failed to write the output file: Permission denied，
> 且旧进程会一直占着它注册过的热键（表现为"某个热键怎么按都没反应"）。

## 仓库结构

```text
winun/
├── cjpm.toml                 # 仓颉模块配置（链接 user32/kernel32/shell32/...）
├── config/
│   ├── winun.json            # 示例配置（v1 规范）
│   └── winun.schema.json     # JSON Schema，供编辑器校验
├── docs/
│   ├── winun-初期设计文档.md
│   └── spike-report.md
├── src/
│   ├── main.cj               # 入口（经 Win32 GetCommandLineW 取参数）
│   ├── cli/                  # validate / list / run / version / smoke
│   ├── app/                  # 宿主：装配、注册热键、消息循环、热重载
│   ├── core/                 # Registry / Session / Dispatcher
│   ├── domain/               # 窗口模型、组、布局声明、动作、组合键、匹配规则
│   ├── layout/               # 纯函数布局解算
│   ├── config/               # JSON → ConfigSnapshot，含校验与错误码
│   ├── platform/             # 平台抽象 trait + Null 实现（便于单测）
│   ├── win32/                # Win32 FFI、句柄表、消息循环、命令行
│   └── infra/                # JSON 解析器、UTF-8/UTF-16、日志、错误
└── spike/                    # M0 最小验证工程（保留作回归参考）
```

## 实现进度

**已实现**

- `infra`：自研严格 JSON 解析器（重复键检测、行列号错误定位、BOM 处理）、UTF-8 ↔ UTF-16 转换、`%VAR%` / `${env:VAR}` 展开、文件日志。
- `config`：JSON → `ConfigSnapshot`，含类型校验、未知键策略（默认警告，strict 下报错）、交叉引用校验、E1xxx/E2xxx 错误码。
- `layout`：grid / ratio / absolute / anchor 四种布局解算 + 溢出堆叠，纯函数可单测。
- `domain`：窗口模型、组/启动集合/应用描述、组合键解析（含 VK 映射表）、动作字符串解析、窗口识别规则（exe/path/class/title 正则、通配符）。
- `win32`：Win32 FFI 声明、句柄表（CPointer ↔ 不透明 ID）、窗口枚举/查询/操作、进程启动、热键注册、消息循环、单实例互斥体、命令行读取。
- `core` / `app`：Registry（应用与组归属）、Session（组状态与焦点记忆）、Dispatcher（启动集合、组切换、布局应用、贴边、最大化/还原）、Host（热键注册 + 消息循环 + 热重载）。

**待实现（M2/M3）**

- `SetWinEventHook` 窗口事件监听（自动收编新窗口）
- `window float toggle`、`window focus-cycle` 的完整语义
- 多显示器按索引选择（`monitor: 0/1`）与 DPI 感知（Per-Monitor V2）
- `winun.user.json` 深合并、托盘菜单、开机自启、日志轮转

## 说明

- 仓颉模块名必须为 ASCII，`cjpm` 在 Windows 上不支持中文路径——请把仓库放在纯英文路径下。
- 详细的平台限制与踩坑记录见 [M0 技术验证报告](docs/spike-report.md)（例如：本环境下 `RegisterHotKey`/`SetWindowPos` 会被沙箱拦截，需在普通交互会话中做端到端验证）。