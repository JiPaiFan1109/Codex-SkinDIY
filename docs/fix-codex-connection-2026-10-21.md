# 已识别安装但未建立连接：修复记录

日期：2026-10-21，北京时间。开发版本 current 1.2.0，未发布。

## 证据和边界

用户提供 1.1.1 用户截图，悬停提示明确为“已安装 Codex 26.1013.4894.0，尚未建立换肤连接”，界面仍写“未找到Codex”。这证明该次安装识别成功，不足以证明具体 CDP/启动失败原因。此前完整审计见 audit-codex-connection-2026-10-21.md。

本次修复确认存在的连接入口和错误呈现缺陷，不宣称已在反馈者机器或该版本 Codex 上完成端到端修复验证。未识别安装时已加入手动选择入口；选择结果仍必须匹配已注册且可验证的官方 OpenAI.Codex 商店包，无法枚举或验证商店包时会拒绝启动并提示原因，避免把任意同名程序当作 Codex。

## 修改

- scripts/skin-manager.ps1：已识别、未连接显示“已找到Codex / 连接未建立”；图标点击进入现有 Open 工作流程，启动前重新检查、启动后验证，不能把子进程退出成功当成连接成功。已连接和预览状态仍只刷新。
- 真实启动仍由 Invoke-DynamicEngine 使用 -PromptRestart 调用既有引擎，不新增强制重启路径；取消单独呈现。连接期间禁用按钮并显示加载状态。
- 检测返回 no-session、state-unreadable、endpoint-unavailable、session-changed、detection-unavailable、connected、install-unavailable 原因；保留可获得的异常，传到悬停信息，不再把它们全部吞掉。
- 连接工作返回新连接状态及失败原因，后台失败路径可更新图标并显示可关闭的原因弹窗；失败信息附启动日志目录。
- scripts/media.ps1：管理器发起的隐藏启动保存到 logs/manager-<token>-output.log、logs/manager-<token>-error.log；每次尝试单独保存。复用原有路径保护、结构化结果和取消处理。

没有改动注册包验证、调试端口所有者验证、商店启动参数回退、用户壁纸库和已安装软件。current 已有原生 TCP 查询与视频缓存修改继续保留。1.1.1 发行包作为证据未编辑。

## 验证

先新增失败测试：确认原图标实际绑定只发起 Refresh、检测状态异常被吞掉，以及隐藏启动没有独立日志。实现后通过回归。

新增五个脚本：

- codex-connect-action.tests.ps1：执行实际点击绑定；安装已识别时进入连接，忙碌/预览/健康连接保护，启动后再验证、取消、错误、启动成功但端点不可用。
- codex-connection-reasons.tests.ps1：状态与端点异常保留、安装/连接分离、会话过期、badge 文案。
- codex-connect-worker.tests.ps1：真实异步 worker/Complete 流程，替换外部启动与发现边界，验证取消/失败/成功、原因弹窗、spinner 结束、按钮恢复；不启动真实 Codex。
- codex-connection-ui.tests.ps1：不展示窗口，通过 WPF 离屏渲染检查 1440×840 和 900×525 两种尺寸的未连接、连接中、失败、已连接状态，核对文字边界及弹窗按钮恢复。
- manager-connect-logs.tests.ps1：临时安装目录中运行真实隐藏子进程，只写固定测试输出和失败结果，验证两次尝试日志与重启确认参数。不会执行真实引擎启动。

完整 Node 测试 46/46 通过。环境没有 npm 命令，使用已发布包固定 runtime/node/node.exe 执行 package.json 中等价的 node --test current/tests/*.test.mjs。

相关 Windows 回归 12/12 通过：以上五个，加 codex-connection、manager-error、manager-feedback、launch-argument-fallback、port-listeners、existing-session、ux-cancellation。没有运行包含安装/可见 GUI 的完整 Windows 集合。

新增测试开发期间发现测试程序未显式加载 PresentationCore，以及日志 fixture 未导入实际使用的路径保护模块；补全测试依赖后通过。NoticeOnly 弹窗先通过失败测试证明缺失，再实现。相关最终通过输出由本会话工具保留。

离屏渲染证据：项目根 `.local-evidence/connection-fix-20261021/connection-<state>-<width>.png`。已目视检查未连接与失败两种状态的大小尺寸；加载/成功另有程序边界检查。源目录没有发布包生成的 Codex 图标时使用现有 fallback，不代表修改产品图标。

只读独立代码审查：未发现需修复的问题；未替代反馈机器实测。

## 后续验收

按用户要求与其他 1.2.0 修改一起打包和发布，当前未安装、打包、上传或发布。获得部署/测试授权后，在真实商店版环境验证：首次点击连接、用户同意/取消重启、成功变绿、失败弹窗及日志留存；若 26.1013.4894.0 仍不能开放端点，用新日志定位启动、参数转发、权限或端口验证的具体阶段。
