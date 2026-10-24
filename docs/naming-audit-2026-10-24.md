# CodexPage 下载名称审计

2026-10-24 核实：源码 2.1.1；GitHub latest 为 v2.1.1，发布提交 41bb36a1dfc5a86b1c8ba7d3858640b3e156e324。公开 API 的六附件只有旧名 EXE、ZIP、各自 SHA256、update.json 和 update.sig。公开结果保存在工作区 `.local-evidence/naming-audit-20261024/release-before.json`。

## 根因与修正

- 构建已有 CodexPage 别名，但 Inno 主输出和 build-app 返回值仍是旧名；已改为 CodexPage-Setup.exe。
- 中英文 README 主链接与安装说明仍指向旧名；已改为 CodexPage。
- `.tools/release-v211.ps1` 只上传旧名六附件，还残留一条被覆盖的错误 ZIP 清单；改为调用完整附件检查器。
- GitHub Actions 同样只点名上传旧 EXE，标题仍是旧品牌；已接入完整附件检查器并修改标题。
- CI 使用 ZIP 通配符，无法明确选择新增的两个别名包；改为按 VERSION 精确选择 CodexPage ZIP。
- 更新发现 API、清单获取地址和 User-Agent 已使用 CodexPage。签名清单的旧 URL 保留为兼容协议。
- 新增 get-release-assets.ps1：要求 10 个附件，检查新旧 EXE/ZIP 内容一致和每个 SHA256 文件正确，全部验证后才返回上传清单。缺少新名、别名字节不符或校验错误会阻止发布。
- 安装器生命周期验证和包测试入口同步使用 CodexPage 主名称。

## 有意保留的旧标识

| 标识 | 保留原因 |
| --- | --- |
| Codex-Skin-Manager-Setup.exe、Codex-Dynamic-Skin ZIP | 旧下载链接、签名更新协议兼容；必须与主文件字节一致 |
| 签名清单中的 Codex-Dynamic-Skin 仓库 URL | 已发布客户端固定校验该完整 URL；修改会导致旧客户端拒绝更新 |
| CodexDynamicSkin 安装目录探测 | 覆盖升级已有安装，避免把用户数据误判为缺失 |
| CodexSkinManager.exe、启动器文件名、互斥量、AppUserModelID、命名空间 | 旧启动入口、单实例协调、升级等待和任务栏身份一致性 |
| codex-dynamic-skin-wallpaper/1 | 现有用户壁纸元数据协议 |
| 旧快捷方式名称 | 安装器迁移清理目标，不是新建快捷方式名称 |
| 签名密钥目录 | 继续使用现有受信任密钥，避免破坏旧客户端信任链 |
| 测试中的旧 URL/目录 | 旧版本兼容与来源校验测试 |

根历史 0.2.3、outputs、previews、旧版本发布脚本及历史发布说明保持原状；不能为了关键词清零而改写历史产物。当前工作流由 `.tools/publish-codexpage-2.0.0` 中已核对的 41bb36a 发布源码复制到 `current/.github/workflows` 后修正；下次同步源码必须包括该隐藏目录，不能继续沿用发布副本内的旧流程。

## 验证与待办

- Node 49/49；packaging-names、release-assets、app-update、update-flow、update-staging、install-location、upgrade-preflight 七组 Windows 回归通过。
- current PowerShell 脚本解析通过；完整附件检查器对已有 2.1.1 本地构建返回 10 个附件，新旧哈希一致。
- 未构建新安装包、未安装、未上传、未修改公开 Release、未重启 Codex。源码仍为 2.1.1 加本地修正，不能视作已发布字节。
- 线上修复需补传现有构建中的四个 CodexPage 文件（EXE、ZIP 和各自 SHA256），再同步 README 新链接；不删除旧六附件。后续发布还需同步 current 的源码和隐藏工作流，并执行实际构建及生命周期验收。

该审计覆盖命名、下载、构建、发布、更新和迁移链路，不等于对所有业务逻辑作无缺陷保证。
