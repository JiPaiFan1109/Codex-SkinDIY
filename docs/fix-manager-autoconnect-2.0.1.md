# 2.0.1 管理中心自动连接

日期：2026-10-23。状态：源码修复及隔离回归完成，未打包、安装或发布。

## 原因与范围

2.0.0 的 ContentRendered 只派发 Refresh，读取当前连接后立即显示结果；失效会话不会因此自动建立新连接。图标点击才派发 Open。本机 2026-10-23 13:23 的 manager 日志记录了归档过期会话后连接到验证端口 8395；这不能单独证明升级导致会话失效。另一次 13:26 启动存在隐藏文档和视频未就绪导致的验证失败，属于独立启动问题，本次不宣称已修复所有连接失败。

复用项目已有 MIT 开源 Codex-Dream-Skin 衍生引擎和 Connect-DynamicCodex，不增加依赖。管理中心首次呈现时派发 Open；工作线程重新检测，健康连接直接复用，未连接时调用既有引擎，保留 PromptRestart 确认和启动后身份验证。连接期间复用加载状态，完成前不显示红叉或假成功。ContentRendered 重入有一次性保护，失败或取消不会自动再次启动；图标仍可手动重试。PrepareOnly 仍只 Refresh。

自动连接可能打开尚未运行的 Codex；已运行且必须重启时仍需用户确认。加载耗时受 Codex 启动、媒体和端点状态影响，不保证打开瞬间成功。原有工作线程在连接期间禁用操作按钮，本次没有引入并发壁纸操作。

## 验证

- 新增真实 ContentRendered 绑定测试，先在旧代码上复现“只检测不连接”的失败，再验证修复。
- 实际异步 worker 隔离测试：启动成功、失败、取消、健康连接复用、预览只读、重复事件、加载期间隐藏 badge、操作完成后释放忙碌状态。
- 8 个 Windows 测试脚本通过：codex-connect-action、codex-connect-worker、codex-connection、codex-connection-reasons、codex-connection-ui、manager-connect-logs、manager-error、manager-feedback。
- Node 测试 46/46 通过。
- 离屏渲染检查 1440×840 和 900×525；已目视查看小尺寸加载和大尺寸成功图。证据在根目录 `.local-evidence/connection-startup-2.0.1/`。未做真实窗口动画或真实启动端到端验收。

开发 VERSION/package.json 为 2.0.1；公开安装包仍为 2.0.0。未修改生产安装、重启 Codex 或变更壁纸库。
