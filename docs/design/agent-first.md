# Agent-First 刘海：设计稿

状态：已确认（2026-11-19）。待定 1 选了"按钮自动信任"。

## 接口约定（两边的 worker 都按这个写）

bridge 发出的请求头，值为空时不发：

| 头 | 值 |
|---|---|
| `X-Agent-Pid` | agent 进程 pid（沿父进程往上找 comm 为 claude / codex 的那个） |
| `X-Agent-Host-Bundle` | `$__CFBundleIdentifier` |
| `X-Agent-Term-Program` | `$TERM_PROGRAM` |
| `X-Agent-Tmux-Pane` | `$TMUX_PANE` |
| `X-Agent-T3-Thread` | `$T3CODE_THREAD_ID` |
| `X-Agent-T3-Environment` | `${T3CODE_HOME:-$HOME/.t3}/userdata/environment-id` 的内容，仅在有 T3 线程时 |

app 侧用一个注入的存活查询闭包（`([Int32]) async -> [Int32: Date]`，查不到的 pid 视为已退出），helper 侧提供实现。字符串目录 `Localizable.xcstrings` 两边都不改，合并后统一补。

## 目标

同时开着几个 Claude Code / Codex 会话（多数从 T3 Code 启动）时：

- 合上的刘海显示几个在跑、几个在等你；
- 一轮回复结束，弹一条横幅并进 Inbox；
- 点一下回到那个会话：T3 线程走 `t3code://threads/<env>/<thread>`，终端则把终端 app 切到前台。

通用通知（`POST /v2/notify`、Inbox、横幅）保持原样。通用 activities 删掉。

## 数据流

```text
claude / codex
  └─ hook（同步）→ ~/.not-boring-notch/bin/notch-agent-hook <agent>     sh 脚本，约 28 ms，永远 exit 0、不输出
        └─ POST /v2/agents/<agent>/events
             body    = hook 原始 JSON，不改动
             headers = X-Agent-Pid / -Host-Bundle / -Term-Program / -T3-Thread / -Tmux-Pane
              └─ ChannelServer → AgentAdapter（每家一张表）→ AgentEvent
                   └─ AgentReducer（纯函数）→ AgentSession + [AgentEffect]
                        ├─ AgentStore（NotchChannel 持有）→ ClosedNotchArbiter → 刘海
                        └─ effects → 现有通知管线（横幅 + Inbox）
XPC helper（不在沙盒）：安装/修复/卸载 hook；按 pid 查进程是否还活着
```

## 比较过的两种形状

| | A. bridge 只转发，换算在 app（选这个） | B. 原生 bridge 先换算成标准事件 |
|---|---|---|
| bridge | 30 行 sh + curl + plutil，无新 Xcode target | 新的 Swift 命令行 target |
| 适配某家 agent 的格式变化 | 改 app 里的表，hook 不用重装 | 改 bridge，要重新安装 |
| 测试 | 适配表和 reducer 都是纯函数，喂 JSON fixture | 一半逻辑在另一个进程 |
| 其他 agent | 表里加一行（Claude 风格的 hook 基本通用）；脚本可走 `generic` 行 | 同样要加适配 |
| 代价 | 每次 hook 约 28 ms（实测，原生约 10 ms） | 多一个 target 和签名 |

## 核心类型

```swift
enum AgentKind: String { case claudeCode = "claude-code", codex }

/// 会话在哪跑。决定身份、点击去向和显示名。bridge 只报事实，这里换算。
enum AgentHost: Equatable {
    case t3Code(threadID: String, environmentID: String?)
    case app(bundleID: String?, termProgram: String?, tmuxPane: String?)
}

/// 按 agent + session_id。实测：在 T3 线程里启动的子 agent（如 Claude 跑 `codex exec`）继承线程环境，按线程作 key 会互相顶掉（2026-11-19 修订）。
struct AgentSessionKey: Hashable { let raw: String }   // "claude-code:<session_id>"

enum AgentWait: Equatable { case approval(tool: String?), question }

enum AgentPhase: Equatable {
    case idle
    case working(tool: String?)
    case waiting(AgentWait)
}

struct AgentSession: Equatable {
    let key: AgentSessionKey
    let agent: AgentKind
    var host: AgentHost
    var cwd: String?                  // 显示名取最后一段
    var process: AgentProcess?        // pid + 首次见到时的启动时间，防 pid 复用
    var phase: AgentPhase
    var turnStartedAt: Date?
    var updatedAt: Date
    var subagents: Set<String>        // 带 agent_id 的子 agent，不改父会话的 phase
}

/// 适配表的输出。各家 hook 名字不同，换算后只剩这些。
enum AgentEvent: Equatable {
    case sessionStarted
    case promptSubmitted
    case toolStarted(name: String?, asksUser: Bool)
    case toolFinished
    case permissionRequested(tool: String?, asksUser: Bool)
    case needsAttention(AgentWait)        // Notification: permission_prompt / elicitation_dialog
    case wentIdle                         // Notification: idle_prompt（Claude 被 Esc 打断后的恢复信号）
    case turnEnded(summary: String?, failed: Bool)
    case interrupted                      // Codex Interrupt
    case sessionEnded
}

struct AgentEnvelope { let agent: AgentKind; let sessionID: String; let subagentID: String?
                       let event: AgentEvent; let cwd: String?; let host: AgentHost; let pid: Int32? }

enum AgentAdapter {
    /// 原始 hook JSON + headers → 信封。不认识的事件返回 nil（静默忽略，不报错）。
    static func envelope(agent: AgentKind, payload: Data, headers: [String: String]) throws -> AgentEnvelope?
}

enum AgentEffect: Equatable {
    case turnFinished(AgentSession, summary: String?, failed: Bool, duration: TimeInterval)
    case needsYou(AgentSession, AgentWait)
    case calmed(AgentSessionKey)          // 撤回这个会话的"等你"通知
}

enum AgentReducer {
    static func reduce(_ session: AgentSession?, _ envelope: AgentEnvelope, now: Date)
        -> (session: AgentSession?, effects: [AgentEffect])
}

struct AgentStore {                       // 和 BannerQueue / NotificationInbox 同一风格
    private(set) var sessions: [AgentSessionKey: AgentSession]
    mutating func apply(_ e: AgentEnvelope, now: Date) -> [AgentEffect]
    mutating func sweep(alive: [Int32: Date], now: Date) -> [AgentEffect]   // 进程没了 → 删除
    var summary: AgentSummary { get }     // working / waiting 计数和最急的那个，给仲裁器和视图
}
```

## Reducer 转换表

照抄 Lookout `SessionReducer` 和 CodeStatus 的子类型白名单，坑来自 CodeStatus 的实测记录。

| 事件 | phase 变成 | effect |
|---|---|---|
| sessionStarted | 新会话 idle；已存在则不变 | |
| promptSubmitted | working，记 turnStartedAt | calmed |
| toolStarted(asksUser) | waiting(.question) | needsYou |
| toolStarted | working(tool)，**正在等待时不变** | |
| permissionRequested | waiting(.approval / .question) | needsYou |
| needsAttention | 已在 waiting 则不变（PermissionRequest 6 秒后还会再来一次） | 仅在新进入 waiting 时 needsYou |
| toolFinished | working；**在等批准的是另一个已知工具时不变**（并行工具） | calmed（若从 waiting 出来） |
| wentIdle | working 或 waiting 变 idle，不通知（Claude 只在没有对话框时才发 idle_prompt，所以 waiting 时收到说明提示被 Esc 关掉了） | calmed |
| turnEnded | idle；若还有子 agent 在跑 → 保持 working | 从 working 来才发 turnFinished |
| interrupted | idle，不通知 | calmed |
| sessionEnded / 进程退出 | 删除 | calmed |
| 带 subagentID 的事件 | 只更新 subagents 集合；PermissionRequest / Notification 例外，照常作用于父会话 | |

兜底：working 状态 15 分钟没有任何事件且进程查不到 → idle，不通知。

## 适配表

| | Claude Code | Codex |
|---|---|---|
| 注册的 hook | SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Notification, SubagentStart, SubagentStop, Stop, StopFailure, SessionEnd | SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, SubagentStart, SubagentStop, Stop, SessionEnd, Interrupt |
| 问用户的工具 | AskUserQuestion, ExitPlanMode | request_user_input |
| Notification | 只认 permission_prompt / elicitation_dialog / idle_prompt；agent_completed、agent_needs_input 是别的会话的，忽略 | 无 |
| 摘要 | Stop.last_assistant_message 第一行 | 同 |
| 注意 | 同步 hook；matcher `*` | 不能 async；命令按空格切分，路径不能有空格；需要信任（见待定 1） |

## 刘海

- 仲裁器：`NotchResident` 从 `.music | .activity(id)` 改成 `.music | .agents`。有会话在 waiting 时 agents 永远排在音乐前面；只有 working 时沿用 `musicAheadOfActivities`（改名 `musicAheadOfAgents`）。
- 合上：左翼是在干活的每种 agent 的图标，叠在一起，有 agent 在干活时慢慢明暗起伏（呼吸）；右翼是灰色数字。有人等你时图标停下、右下角亮琥珀色点，右翼显示 `! 1 | 2`：琥珀色的等待数，浅色竖线，灰色的干活数。
- 横幅：回合结束 → active 级通知，标题是项目名，正文是摘要（横幅里显示在刘海下方一条，见第三层 sneak peek），`thread` = 会话 key，`open` = 跳转目标。等你 → time-sensitive 通知，同一会话 calmed 时撤回。不足 10 秒的回合不弹横幅，只进 Inbox。
- 展开：Inbox 顶部是"Agents"一节，每个会话一行（图标、项目名、状态、计时），点击跳转。

## 跳转

| host | 动作 | 权限 |
|---|---|---|
| t3Code | `t3code://threads/<env>/<thread>`，env 来自 `X-Agent-T3-Environment` 头；缺失时只激活 T3 app | 无 |
| app | 按 bundle id 激活那个 app | 无 |

终端里切到具体标签页（iTerm/Terminal 的 AppleScript）第一版不做。

## XPC helper 新增

```swift
func agentProcessStartTimes(_ pids: [NSNumber], with reply: @escaping ([NSNumber: NSNumber]) -> Void)  // 查不到 = 已退出
func agentHooksStatus(with reply: @escaping (Data) -> Void)          // 每家：未安装 / 已安装 / 被改动
func trustCodexHooks(with reply: @escaping (Data) -> Void)           // 经 codex app-server 写 hooks.state（Lookout CodexTrust）
func installAgentHooks(_ agents: [String], hookScript: String, with reply: @escaping (Data) -> Void)
func uninstallAgentHooks(_ agents: [String], with reply: @escaping (Data) -> Void)
```

安装：写 `~/.not-boring-notch/bin/notch-agent-hook`（路径无空格，Codex 需要）；`~/.claude/settings.json` 和 `~/.codex/hooks.json` 用 CodeStatus 的 `JSONSurgeon` 做逐字节保留的编辑（先删自己的条目再追加，备份，写前校验文件没被并发改动）；`~/.codex/config.toml` 打开 `features.hooks`（照 CodeIsland `CodexHooksConfig`）。只在用户点"安装"后才写；之后每次启动只修复自己装过的。

## 删除

`ChannelActivity.swift`、`ActivityStore.swift`、`/v2/activities` 路由、`ActivityTests`、文档和 playground 里的 activity 部分。`ActivityViews` 里的圆环和计时器只保留 agents 视图用得到的。

## 抄自哪里（保留 MIT/Apache 声明）

| 部分 | 来源 |
|---|---|
| reducer、子 agent 处理 | Lookout `Sources/LookoutCore/AgentSession.swift:139-244` |
| Notification 子类型白名单、问用户的工具 | CodeStatus `Sources/CodeStatusCore/Domain/AgentEvent.swift:66-86` |
| settings.json / hooks.json 编辑 | CodeStatus `Installation/JSONSurgeon.swift`、`HookInstaller.swift` |
| config.toml `features.hooks` | CodeIsland `CodexHooksConfig.swift` |
| 进程存活 + 启动时间 | CodeStatus `ProcessInspector.isAlive` |
| 回合结束卡片的节奏 | CodeIsland `AttentionPolicy` |

## 实施顺序（每步都能单独验证并提交）

1. 删除通用 activities；刘海暂时只有音乐常驻。验证：测试和构建通过。
2. 类型 + 适配表 + reducer + `AgentStore`，纯函数测试，fixture 用 Lookout 的 `claude-turn.jsonl` / `codex-turn.jsonl`。
3. 路由 `/v2/agents/<agent>/events`（这个路由的 body 上限放到 4 MiB），接入 `NotchChannel`，effects 走通知管线。验证：curl 回放 fixture。
4. 仲裁器和视图。验证：截图。
5. helper：存活查询、hook 安装/卸载、设置面板。验证：在临时 HOME 里装、卸，比对文件字节。
6. 真机：T3 里跑 Claude，再跑 Codex，看计数、横幅、跳转。

## 待定

1. Codex hook 的信任：要么像 Lookout 那样，用户点按钮后通过 `codex app-server` 自动信任；要么让用户在 Codex 里自己审核一次。T3 里的 Codex 走 app-server，可能根本不会弹审核提示，所以我倾向前者。
2. Codex 在 T3（app-server 模式）下会不会触发 hooks，要在第 6 步实测。CodeStatus 也标的是未验证。
