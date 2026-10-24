# 应用内更新

v0.3.0 在原有 WPF CodexPage 和 Inno Setup 升级流程上增加更新检查和下载，不引入常驻服务。用户已批准应用内提醒、一键升级和发布新版本。

CodexPage 在首次加载完成后异步检查 GitHub 最新正式 Release。每天最多一次，包括失败请求；手动检查忽略时间限制和跳过版本。只接受更高的三段数字版本，忽略预发布。版本提示、更新摘要和操作位于窗口底部。断网不会弹出自动错误对话框或阻塞壁纸管理。

每个 Release 必须包含 `update.json`、`update.sig` 和 `Codex-Skin-Manager-Setup.exe`。清单将版本、固定仓库下的版本专属下载地址、SHA-256、长度、说明绑定在一起，以 RSA/SHA-256 签名；应用内置公钥。此签名用于更新认证，不是 Windows Authenticode 证书，Windows 仍可能提示未识别的发布者。发布者私钥不随源码或安装包分发。

用户确认更新后先下载到独立临时目录，重新验证签名、长度和哈希。下载失败不替换程序文件。独立 PowerShell 更新进程等待 CodexPage 和启动器退出，再次校验并锁定安装包，运行静默安装，禁止自动重启电脑，核对已安装版本后重新打开 CodexPage。安装器仍负责验证后台身份、处理占用、保留壁纸库和设置。不终止 Codex 会话；不承诺通用事务回滚，安装器失败或版本不符会报告失败并保留安装日志。

检查状态保存在安装目录 `update-state.json`，安装结果通过 `update-result.json` 在下次启动显示。下载失败清理临时包，安装成功删除已下载 EXE；失败时保留临时目录中的日志与包以便诊断。没有启用应用时的推送，没有增量包和自动强制安装。

## 发布

1. 更新 VERSION、package.json、启动器程序集版本，以及中英文说明、更新记录和 `docs/releases/vX.Y.Z.md`。`engine/VERSION` 是上游引擎协议版本，不随应用版本修改。
2. 构建 EXE/ZIP，运行 Node、Windows 测试与隔离安装生命周期检查。
3. 运行 `scripts/sign-update.ps1 -OutputDirectory dist -NotesPath docs/releases/vX.Y.Z.md`，该脚本校验生成的签名与包哈希。
4. 先运行 `scripts/get-release-assets.ps1 -OutputDirectory dist -Version X.Y.Z`，完整上传其返回的 10 个附件：CodexPage EXE/ZIP 及各自校验文件、旧名兼容 EXE/ZIP 及各自校验文件、update.json、update.sig。检查通过后才创建草稿并上传、核对、发布。禁止仅上传旧名六附件。

主下载入口使用 `CodexPage-Setup.exe`，压缩包使用 `CodexPage-X.Y.Z-windows-x64.zip`。旧名文件是字节一致的兼容副本。旧客户端把签名清单内的历史仓库 URL 和安装包名作为固定来源校验，所以清单继续使用旧 URL；更新查询入口使用 CodexPage 仓库。不能直接删除旧附件或修改签名 URL，否则已有客户端会拒绝更新。

本机签名私钥默认存储在 `%LOCALAPPDATA%\CodexDynamicSkinReleaseKeys\update-rsa.dpapi`，由当前 Windows 用户的 DPAPI 加密。发布工作流从仓库 Actions secret `UPDATE_SIGNING_KEY_XML` 读取私钥。不要在日志中输出私钥，也不要重新生成公钥后直接发布：已安装应用信任原公钥，换钥需要单独设计迁移。请保留当前 Windows 用户和密钥文件的安全备份。

验证覆盖：数字版本排序/降级、每日检查和时钟回拨、跳过和手动覆盖、离线、伪造清单、下载大小/哈希、独立安装器退出码、重复升级、用户数据保留，以及真实安装器的安装/升级/卸载。旧版没有更新入口，必须先手动升级一次。
