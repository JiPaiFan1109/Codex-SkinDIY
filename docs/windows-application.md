# Windows 安装应用

版本：1.0.0。目标为 Windows x64，用户已安装官方 Microsoft Store OpenAI.Codex 包。

## 应用与本机 Codex

`CodexSkinManager.exe` 是带专用图标的 Windows 图形入口，通过隐藏的 Windows PowerShell 5.1 STA 进程加载现有 WPF CodexPage。入口持有命名互斥量，避免同时打开多个管理窗口，并让安装器检测 CodexPage 是否仍在运行。

CodexPage 通过现有 `Get-DreamSkinCodexInstall` 检测当前用户注册的官方包，显示版本与可供查看的安装路径。找不到包或验证失败时保留壁纸库管理功能，禁用应用和打开 Codex；点击左下连接图标会再次查询。检测到安装表示找到了受支持客户端，不表示已经完成当前会话的皮肤注入。点击应用后仍由原有引擎完成启动、调试连接、注入和结果验证；涉及关闭会话时沿用原有确认提示。

首版没有新增非 Store 安装检测，不支持 macOS、Linux 或 Windows ARM64。Codex 本体不随安装包分发，不需要用户提供 API Key。

## 安装、升级和卸载

安装器支持选择安装目录，重装默认沿用原目录；自动更新通过 /DIR 保持实际安装位置。

EXE 安装不会接管用户原有的 Codex 桌面快捷方式；CodexPage 的「打开 Codex」和开始菜单的「打开换肤版 Codex」进入皮肤启动链路。原有 ZIP 安装方式仍沿用其兼容快捷方式处理。

卸载程序在删除文件前调用 `scripts/uninstall-app.ps1`，检查换肤状态并执行原有恢复流程。取消或失败阻止卸载。静默卸载遇到换肤状态会拒绝执行，用户需先在 CodexPage 恢复外观。卸载仅移除安装程序登记的文件，壁纸库和其他用户状态保留。编译器仅是开发工具，不包含在发行包中。

## 可复现构建

先安装 Inno Setup；本次使用 7.1.0 x64，官方安装器 SHA-256：

`0362a383ed217d4c4239b5933866dd96d3eb2102737da92f80f6057a4b40df2f`

在 Windows PowerShell 5.1 中执行：

```powershell
.\scripts\build-app.ps1 -IsccPath 'C:\path\to\ISCC.exe' -OutputDirectory .\dist
.\scripts\test.ps1 -NodeRuntimePath .\dist\app-package\engine\runtime\node\node.exe
.\installer\verify-setup.ps1 -IsccPath 'C:\path\to\ISCC.exe'
```

输出目录应为空，构建不会覆盖已有安装程序。默认下载并校验固定 Node.js 运行环境，也可使用 `-NodeRuntimePath` 指定已经校验过的官方可执行文件。输出 EXE、ZIP、各自的 SHA-256 文件及用于检查的 `app-package`。GitHub 仅上传 EXE、ZIP 和校验文件，不上传本地证据、构建工具或用户状态。

安装器支持选择安装目录，重装默认沿用原目录；自动更新通过 /DIR 保持实际安装位置。

发行程序没有项目代码签名证书；Node.js 的上游签名验证不代表本项目 EXE 已签名。使用 Release 校验文件核对下载内容，不要求关闭 Windows 安全保护。
