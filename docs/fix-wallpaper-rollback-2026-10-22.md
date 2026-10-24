# 运行中换壁纸被误回滚

## 复现与证据

用户复现：Codex 运行中，CodexPage 从地球切换到篝火，画面成功变化；彻底退出后经桌面快捷方式重新打开，出现未验证到壁纸连接的重启提示，壁纸回到地球。

2026-10-22 只读核实本机 `%LOCALAPPDATA%/CodexDynamicSkin/VERSION` 为 **1.2.1**；此前工作区“本机 1.1.0”已过时。安装目录的 media.ps1、wallpaper-library.ps1、start-dream-skin.ps1 与修改前 current 文件哈希相同。

本机日志显示：18:04:51–18:05:06 的管理器调用完成现有连接应用，并写入成功结果；紧接着第二次调用在 18:05:18 提示重启。磁盘 video-theme.json 指向旧地球，与本次 media-rollback 备份一致，最后修改时间仍为 10 月 19 日。第二次调用中的 Codex 主进程已经携带调试端口及管理 profile 参数，因此不能把截图直接归因于用户用了原始入口。

## 确定的缺陷

在 Windows PowerShell 5.1 下，`Start-Process -PassThru` 同时重定向标准输出和错误后，如果没有提前保留进程句柄，`HasExited`、`WaitForExit()`、`Refresh()` 后的 `ExitCode` 可以是 `$null`。本机独立隐藏子进程重现了此行为。

`Invoke-DynamicEngine` 即使读到结构化成功结果，仍因 `$null -ne 0` 抛出“应用操作失败（退出码 ）”。`Invoke-DynamicBackgroundTransaction` 随即恢复旧壁纸文件，再次调用引擎。这与日志中的相邻两次成功调用、旧配置恢复相吻合。第二次调用遇到退出或启动中的 Codex 时可能产生截图的提示；没有真实重启来逐帧验证弹窗时序。

## 修改

仅在 `scripts/media.ps1` 启动引擎子进程后读取并保留 `$process.Handle`，使等待后的退出码可读取。保留原有结构化结果校验、非零退出码失败、取消和真正失败的回滚语义。没有删除重启确认保护，也没有修改用户壁纸选择。

## 验证范围

- 新增 `tests/media-process-result.tests.ps1`，在临时 LOCALAPPDATA 中用真实 Windows PowerShell 子进程验证管理器边界。修复前成功用例报“退出码空”并失败；修复后通过。
- 隔离地球 → 篝火配置切换，经过真实主题初始化后仍保存篝火，成功操作仅有两次引擎调用，没有额外回滚调用。媒体和引擎为测试夹具，不代表真实视频播放验收。
- 成功恢复、真实退出码 7、缺少结果、结构化失败、取消应用与取消恢复通过。
- Node 测试 46/46 通过。环境没有 npm 命令，直接执行 package.json 中等价的 `node --test tests/*.test.mjs`。
- 7 个相关 Windows 脚本通过：media、wallpaper-actions、fast-apply、fast-resume、start-cancellation、manager-error、existing-session。未运行完整 Windows 安装与桌面交互套件。
- 独立审查未发现阻断问题，且单独重跑新增测试通过。fixture 有 350 ms 延迟，未覆盖子进程在获取 Handle 前已退出的极短时序；此边界不是已经证明的回归。

上述为修复阶段记录。随后用户明确要求创建并安装 2.0.0，已于同日完成：

- `VERSION`、`package.json` 和变更记录统一为 2.0.0；构建输出 `outputs/release-2.0.0/`，69 项包清单校验及 app-package 测试通过。
- EXE SHA-256：`655fe193b11d34b75c9c977e7cee1ec0f96ebbd8d06ff5a1f68199227458dce3`。
- ZIP SHA-256：`b9d6770d4205e6c9a86348142889f82ec64f88fda2b0d7009e1fc9205559f907`。
- 隔离 1.2.1 → 2.0.0 覆盖安装、文件哈希、视频模块导入及卸载保留用户库均通过；第一次因 CodexPage 运行锁退出，关闭 CodexPage 后重跑通过。
- 本机静默覆盖安装退出码为 0，VERSION 为 2.0.0，52 项安装脚本/引擎/外观文件与包一致；安装前保存的 22 项用户配置/壁纸文件哈希完全保留。证据在 `.local-evidence/release-2.0.0/`。
- 未主动重启 Codex、未执行真实壁纸切换、未公开发布。部署后当前 Codex 会话没有可验证的 9345 壁纸连接，所以未执行真实热切换验收。早期进程快照在安装前已失效，不能声称整轮 Codex 始终是同一个进程。

结论：正常连接下支持运行中换壁纸，已修复确定的误回滚缺陷；最终仍需在有连接的真实会话中验证切换及完全退出重开。无可用调试连接的独立启动场景仍可能需要一次确认重启，不能承诺任意入口永不提示。

## 安装后真实热切换验收

后续进一步检查发现，正在运行的 Codex PID 21508 使用 8395 端口，旧 state.json 保存的是 9345。8395 经既有进程归属校验通过；先前仅检查旧端口就停止验证不充分。

使用本机已安装 2.0.0 的 `Use-DynamicWallpaper` 和 `Invoke-DynamicEngine`（CodexPage 同一应用链路），真实执行地球→篝火：两次应用均成功，配置中的内容哈希分别匹配目标壁纸；每次应用后 Codex PID、创建时间和 BrowserId 均未变化。两次应用恰好产生两次引擎调用，无额外回滚。最终渲染检测 pass=true，video.ready=true、video.playing=true，持久配置保留篝火。证据：`.local-evidence/release-2.0.0/live-switch-*`。首次测试启动因宿主继承的 PSModulePath 无法加载 Get-FileHash，在改壁纸前失败；测试脚本恢复标准 Windows PowerShell 模块路径后重跑通过，未改产品代码。

此为真实后端应用及渲染验收，没有声称通过 GUI 点击完成。用户明确选择保留当前对话、不进行关闭重开测试；因此完整退出后经原桌面入口重开的流程仍未验收。当前桌面发现同名 Setup EXE，未确定用户所说快捷方式的准确入口。
