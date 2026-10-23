# 1.1.0 已发布

发布日期：2026-10-20（北京时间）。用户已授权检查通过后直接发布，并要求更新 GitHub 主页预览图。

- 发布页：https://github.com/JiPaiFan1109/CodexPage/releases/tag/v1.1.0
- GitHub main 与 v1.1.0 标签均指向：5e0195176a19c8631f80d3ba0a497540d2360b02。
- 公开源代码本地副本：.tools/release-publish-1.1.0（工作区干净）。候选源 outputs/release-candidate-1.1.0；新增运行修正已同步第九版草稿。
- 最终发布资产：outputs/release-1.1.0-final。早期 outputs/release-1.1.0 已标记为被替代，不可重新发布。
- 安装包 SHA-256：5117910ee4c02a82693c1c10cb760d10241a47ef3b6f755b8bdbfe13a051f881。
- EXE、ZIP、两份校验文件、update.json、update.sig 共六项资产均上传校验通过，正式发布为最新稳定版。
- 更新说明使用用户确认的简短版本；应用内使用纯文本说明，避免显示 Markdown 标记。
- 中英文主页均引用 docs/images/skin-manager-v1.1.0.png，新图由最新 WPF 界面渲染，完整画廊预览；公开图片 blob 与本地一致。

## 已解决的发布问题

- 补全发布清单中的 existing-session.ps1、multi-instance.ps1 和更新进度窗口依赖。
- 多窗口监测写入进程及工作子进程身份；安装前验证路径、启动时间、父进程和启动参数，先停止监测再停止子进程，不终止 Codex。
- CodexPage 重新打开后恢复已有壁纸状态的监测。

## 验证

- 31 项 JavaScript 测试，更新、连接复用、多实例、清晰度和界面回归通过。
- 隔离的真实 PowerShell 监测和原生工作进程退出测试通过。
- 实际 Inno 全新安装、模拟 1.0.1 到 1.1.0 的签名更新安装测试通过；后台占用正确退出，壁纸库和保存状态保留。
- 最终安装包路径保护、校验值与应用身份审计通过。
- 公开验证：模拟旧 1.0.1 客户端发现 1.1.0、验证更新清单签名，实际下载公开 EXE，SHA-256 与本地最终包一致。
- 证据：.local-evidence/release-1.1.0/isolated-install-result.json、public-verification.json。

未修改用户当前安装或重启当前聊天窗口。整机重启、睡眠唤醒及所有第三方入口仍不构成全面兼容保证。