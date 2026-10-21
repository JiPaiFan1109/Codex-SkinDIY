# Codex 红 × 连接逻辑审计

日期：2026-10-21（北京时间）。用户反馈多个微软商店版用户显示红 ×，用户估计壁纸软件为 1.1.1。以本地已核验的 `outputs/release-1.1.1/app-package/` 为发行代码证据，交叉检查 current 1.2.0。未确认反馈者的实际版本及环境，未声称复现其具体根因。

## 范围与验证

- 审查安装发现、状态读取、TCP 归属、CDP HTTP 身份、页面筛选、启动与回退、管理器异步刷新、按钮与错误处理。
- 1.1.1 与 current 的 scripts/skin-manager.ps1 SHA-256 相同：B026DD757857C43282F3CA00654551F878C3ED298478E78D31DD4D4AE68F9635。
- `.local-evidence/connection-audit-20261021.ps1` 在 Windows PowerShell 中模拟两版各 7 种情况，共 14 项通过。使用实际检测与 badge 函数，替换外部查询并用普通对象代替控件；只加载 WPF 程序集，不创建窗口，不启动或停止 Codex。
- current 的 launch-argument-fallback.tests.ps1 与 port-listeners.tests.ps1 通过。这是当前源码回归，不能当成 1.1.1 端口实现的验证。
- 首次运行新增证据脚本因 UTF-8 无 BOM 被 Windows PowerShell 误读中文而失败；转为 UTF-8 BOM 后完整通过，未修改产品脚本。
- 前一轮本机只读验证：Store 包 OpenAI.Codex 26.1016.6573.0 能识别，Available=True、Connected=False。单机结果不排除其他机器的商店包或权限差异。

## 红 × 的准确条件

`scripts/skin-manager.ps1:649` 的 Update-DynamicManagerConnectionBadge 默认红 ×，只有 Connection.Connected 为真才绿勾。所有非真值（含初始对象缺少 Connected、旧检测结果）均显示红 ×，并写死“连接失败 / 未找到Codex”。Available=True 也一样。

`scripts/skin-manager.ps1:9` 的 Get-DynamicCodexConnection 只有下面全部成立才 Connected=True：

1. Get-DreamSkinCodexInstall 成功，得到注册商店包。
2. Read-DreamSkinState 命令存在，默认 `%LOCALAPPDATA%/CodexDynamicSkin/state.json` 可读取且有 port。
3. Get-DreamSkinVerifiedCdpIdentityForAnyRegistered 在该端口找到可信 Codex 调试端点。
4. 返回的 BrowserId 与 state.browserId 相等。

安装查询外层异常返回 Available=False，并保留 Error 字符串但通用 Message 不含具体异常。状态和端点探测内层 catch 为空，异常被吞掉，Available=True、Connected=False、Error=null。没有状态文件和不合格端点也走相同未连接结果。

## 确定存在的行为问题

1. **错误归因**：已识别安装但未连接也显示“未找到Codex”。隔离复现覆盖状态缺失、状态异常、校验异常、端点拒绝、BrowserId 不匹配。
2. **重新检测不建立连接**：OpenButton 点击绑定 Refresh（522 行），Refresh 分支为空（385 行附近），仅前置读取连接。实际启动发生在 Apply 调用 Invoke-DynamicEngine，或外部壁纸启动入口；管理器虽保留 Open 操作实现，左下角按钮不绑定该操作。首次进入管理器、未应用壁纸时红 × 可以只是尚未启动换肤会话。
3. **错误信息丢失**：状态/校验异常无法从连接 Error 或悬停提示恢复；安装查询 Error 也没有被 badge 悬停文字展示。仅靠用户截图或悬停不能保证找出真实失败阶段。
4. **状态不是持续监控**：管理器打开触发一次 Refresh；手动点击和 Apply/Open/Restore 重新检查；其他操作复用 PreviousConnection。120ms DispatcherTimer 仅轮询当前后台任务，不是连接健康轮询。Codex 随后成功启动或更新，界面可能仍红；反之也可能保持旧绿勾。
5. **失败操作保留旧连接对象**：后台任务在 Apply 等操作抛错时，不返回后置连接结果；Complete 的 catch 只显示操作错误，finally 重画此前 Connection。因此红 × 可反映上一次状态，而不是本次失败的准确原因。
6. **状态依赖过强**：检测只看 state 指定端口和 browserId，不主动发现另一个有效端口。引擎启动流程有 existing-session 发现能力，但检测按钮不执行它。状态丢失或陈旧时，真实可用端点存在也可能红 ×。
7. **绿勾也非壁纸健康证明**：该函数不检查注入器 PID 是否存活、不检查暂停标志、实际页面壁纸或视频服务，仅验证 CDP 与记录身份。注入器死亡但端点仍有效可能绿勾；这不是本次红 × 的直接原因，却说明状态含义需要明确。

补充：Update-DynamicManagerButtons 在 194 行强制 OpenButton.IsEnabled=True，所以检测失败后仍能点击重试；不能仅根据 Get-DynamicManagerActionState.Open=False 推断图标被禁用。Busy 时点击会被 Start-DynamicManagerWork 的早退忽略。

## 安装发现失败的全部主要门槛

发行 common-windows.ps1:495–550：仅查询当前调用上下文的 Get-AppxPackage -Name OpenAI.Codex，不使用全用户扫描。候选必须 Name 完全匹配、InstallLocation/PackageFullName/PackageFamilyName 存在、SignatureKind=Store、非开发模式；固定检查 app/ChatGPT.exe 存在；读取 manifest，必须恰好一个 Application.Executable 匹配该路径；FamilyName 与 Application Id 满足字符及长度规则。

因此以下环境差异均可能变成“没找到安装”：

- 软件以另一个 Windows 账户运行，该账户没有同样的注册包。管理员身份本身不等于不同账户，不能直接据此断言。
- Appx 模块/查询不可用或注册信息读取失败；Appx 查询异常被外层通用提示替代。
- 包在安装、更新或注册切换期间暂时不完整；WindowsApps 路径/manifest 无法读取。
- 某个包版本改变包名、EXE 路径或 manifest 应用布局；现有代码强绑定名称和 app/ChatGPT.exe。未发现反馈机器确实出现这些变更的证据。
- 包并非满足当前验证规则的 Store 签名注册包。不能据此建议取消来源校验或放宽任意 EXE 注入。

代码本来就是优先面向官方商店包设计；“商店下载”不是单凭源码即可认定的不受支持安装方式。

## 已识别安装后，端点仍被拒绝的条件

发行 common-windows.ps1:881–945：

- Get-NetTCPConnection 命令缺失、NetTCPIP/CIM 查询失败，或返回空监听列表。1.1.1 用 Get-NetTCPConnection，进程身份另用 Get-CimInstance；current 已改原生 TCP 表及 Get-Process，不能把该优化当成已交付给 1.1.1 用户。
- 指定端口无人监听，Codex 已关闭，端口改变或被其他进程占用。
- 任一监听地址不等于 127.0.0.1/::1（含 0.0.0.0/::），被安全拒绝。
- 任一监听进程路径无法查询，或与已验证注册包 EXE 路径不一致；权限边界、进程退出竞态、包版本变化都可能触发。
- 商店更新后旧进程仍在，而旧目录不再包含于 Get-AppxPackage 返回的注册候选；即便有“任一注册版本”支持也只能覆盖仍被返回且可验证的旧包。
- 127.0.0.1 的 /json/version 或 /json/list 请求失败、超时（默认每次 1500ms）、非 200、响应 JSON 无效。
- 浏览器 WebSocket URL 不是有效本地 ws 地址，端口、路径、ID、query/fragment 不符合要求。
- 页面列表没有 type=page、url=app://*、合法 id、匹配 /devtools/page/id 的目标。页面启动尚未完成或未来页面 URL 协议变化会导致拒绝；没有证据证明反馈用户发生协议变化。
- 第二次端口归属复核失败（握手前后防止归属变化）。
- 以上通过，但浏览器重启导致 BrowserId 与记录不匹配。

loopback-http.ps1 显式 Proxy=null，因此普通系统代理配置不是这条 HTTP 链的首要怀疑对象；安全软件拦截本地连接仍属于待验证环境因素。该连接走本机回环，不需访问 OpenAI 远端服务才能完成身份判断。

## 为什么换肤端点可能从未建立

start-dream-skin.ps1 启动链区分已有会话、重启授权、商店激活、EXE 回退、CDP 等待、注入与渲染校验：

- 用户只通过原始 Codex 入口启动，进程没有可验证调试端点；引擎需要重启确认，拒绝或取消后不会建立会话。
- 商店激活将参数丢弃或当作 codex:// 导航：已有直接启动已验证 EXE 的回退，但回退可能被拒绝访问、启动失败，或仍不保留参数。
- 参数状态 uninspectable 不触发上述直接启动回退；会继续等待，最终可能端点超时。这个分支是需补诊断的盲点，不能把它直接认定为用户根因。
- 即便参数存在，运行时可能不开放调试端点；代码对此给出 45 秒超时及可能禁用 CDP 的错误，这不是已经证实某版 Codex 禁用的证据。
- 端口不可用、状态恢复冲突、多版本/多实例歧义、旧进程无法安全管理，会阻止继续启动。
- Node runtime 缺失或签名不合格、注入器提前退出、主题/视频准备失败、页面渲染校验失败等，也可能使流程无法写出或保留有效 state。应以启动结果类别及日志定位；红 × 自身不能区分。

state 在注入器启动后写入（约 604–631 行），因此仅安装软件或打开普通 Codex 不保证存在有效 state。state 的 schema/platform/必需字段/端口/PID/browserId 校验失败也会拒绝读取。

## 排查及修正优先级

这是按代码覆盖与获取证据成本排序，不是对反馈用户根因的统计概率：

1. 分离“安装未发现、已安装未启动换肤、正在启动、端点不可用、记录过期、检测异常”；保留失败阶段和具体错误，并记录更新时间。
2. 确认用户是否真正执行过应用壁纸/壁纸启动入口，还是一直点击仅做 Refresh 的图标。完善连接入口，使重新检测与实际建立连接的含义明确，任何必要重启仍保留用户确认。
3. 给 Appx/manifest、state、监听查询、进程路径、HTTP、目标筛选、browserId 各阶段补只读诊断结果。保留端点归属及 Store 来源校验。
4. 重点对 1.1.1 的 NetTCPIP/CIM 故障、权限可见性、商店参数转发、升级后包路径变化进行实机证据比对。
5. 采用 current 已有原生 TCP 表优化时继续做兼容验证；它不能修复所有状态、入口和启动问题。

用户机后续最有价值的证据：壁纸与 Codex 实际版本、同账户 Appx 信息、state 是否存在及仅必要字段、监听归属/命令行参数检查、失败的 .start-result-<token>.json 类别、injector-error.log、verify.log。不要把含账户或命令行敏感内容的原始日志无筛选公开。

本次仅新增审计报告和本地隔离复现材料，没有修改产品逻辑、安装、打包、上传、发布或重启 Codex。
