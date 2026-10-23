# 2.0.1 安装目录与 Steam 引用（2026-10-23）

## 状态

修改在 current 2.0.1 源码中。未构建发行包、安装、上传、发布或重启本机 Codex；正式 EXE 界面及完整安装生命周期仍待打包后验收。

## 安装位置

- Inno Setup 显示目录选择页，重装默认读取上次安装目录。
- 移除固定目录拒绝逻辑；自动更新显式传入当前目录 `/DIR`，支持中文和空格。
- 启动、恢复、主题、视频、手动 Codex 定位记录从实际安装目录读取。
- 管理器真实操作仍要求安装和状态目录一致，隔离预览不启动真实应用。
- 用户需要选择可写目录。更换安装目录不自动搬迁原壁纸库。
- `installer/verify-setup.ps1` 已改为使用不同于编译默认值的 `/DIR`，待允许构建后执行。

## Steam 与本地导入

- Steam 项目读取 project.json 的单个图片/视频文件，记录绝对路径、大小及 SHA-256，不保存媒体副本。仅存索引和缩略图。
- 静态背景使用 externalSource 引用，PowerShell 与 Node 加载器均验证文件身份；仍禁止普通主题目录穿越。
- 视频继续使用现有安全播放链路，从源路径读取；Steam 视频不读写持久视频缓存，播放需要内存缓冲。
- 直接视频限现有兼容条件：H.264 MP4、至多 1080p/60fps、128 MiB。不能直接播放的格式明确报需本地导入，不偷偷转码。
- 本地导入继续复制/转换，不能通过内容去重复用 Steam 引用。
- 失效引用不再出现在列表；管理中心空闲时每 3 秒检查已显示引用是否还存在，消失时重载列表并释放预览。索引及小缩略图保留，源盘重新连接后刷新可恢复记录。
- 当前源文件消失：状态不再报告损坏壁纸，watcher 清除覆盖层；下次经应用启动 Codex 时设置暂停并调用原始启动，不加载缺失文件、不替换成其他壁纸、不要求重启当前 Codex。
- 删除应用中的引用只删除自己的记录，不删除 Steam 源文件。

## 旧数据边界

刷新发现内容完全一致的旧 Steam 专用副本时，沿用原 ID、名称、排序和强度并转换为引用，删除已核实的副本。当前正在使用的旧副本暂缓迁移，先切换或恢复后再刷新。旧版转码视频若不再满足直接播放条件，不自动删除；Steam 和本地共享来源的副本仍作为本地收藏保留。不会在没有核对源文件时批量清空旧库。

## 验证

- Node 48/48 通过，包括外部图像身份、删除检测、视频持久缓存禁用及既有渲染/视频回归。
- Windows 脚本通过：install-location、update-flow（中文空格路径）、update-staging、wallpaper-engine（直接引用/源删除/本地独立副本）、steam-video-reference（真实兼容视频/不支持格式/旧副本迁移/移除不删源）、steam-source-startup（提取真实启动分支、替换外部进程边界）、wallpaper-import、wallpaper-actions、wallpaper-preview、media-restore、media-cli、restore-result、uninstall-app、fast-resume、start-cancellation、quick-launcher-shim、quick-launcher-coexistence、codex-connect-action、codex-connect-worker。
- 所有 PowerShell 源码和测试解析通过。
- 首次媒体测试误用了 PATH 中 OpenAI 签名 Node，被现有签名检查拒绝；改用已发布包内固定 Node 后重跑通过，未放宽签名检查。
- 恢复测试原先依赖 LOCALAPPDATA 重定向，已调整为真实安装目录结构以测试新目录解析。
- 未宣称真实 Steam 库、生产 Codex、GUI 动画或正式安装包端到端验收通过。
