# 多实例壁纸监测（开发版本）

所有可验证的官方 Codex 实例跟随 CodexPage 当前壁纸。后台按进程声明的调试端口发现实例，验证注册安装、回环监听归属及 browser ID 后，为独立连接启动 watcher。同一实例的多个页面由现有 watcher 处理。不会扫描任意网络端口，不会自动关闭或重启 Codex。

源文件：engine/scripts/multi-instance.ps1。启动脚本及快速启动入口会启动它；每个 StateRoot 使用独立互斥锁，防止重复服务。当前电脑已为安装目录注册 HKCU Run 的 CodexDynamicSkinInstances；未来打包时需加入对应安装/卸载注册步骤，尚未构建安装包。

日志：状态目录下 multi-instance-status.json 和 logs/multi-instance/。不提供调试端口的 Codex 进程列在 ProcessesWithoutConnection，无法在不重启的情况下获得壁纸；本版本不更改第三方账号或启动设置。

测试覆盖三个模拟连接、排除 renderer、连接身份改变、重复扫描不重复启动、实例退出、更换壁纸后重新连接、恢复时清理。已实测两个独立 Codex 进程（12911、12912）：静态壁纸真实画面、动态视频 ready/playing、关闭后的 watcher 清理、重开后的自动重连均通过。主动终止隔离测试的视频服务后，监测自动启动新服务并恢复播放。接回安装目录后，主实例启动验证及第二实例动态播放验证通过。第三方工具直接启动、无调试入口进程和整机重启仍未完成端到端验证。

恢复原始外观删除 state.json 后，监测会清除其管理的额外壁纸并等待下次启用。源代码变更在 v8 草稿；之前版本保留。

## 2026-10-20 实机续测
- 正常启动脚本显式指定已有端口时，之前跳过连接复用，可能另启同端口进程。现在显式端口仅采用该端口的已验证连接，缺失时不会误选其他端口。新增对应回归断言。
- state.json 缺失时监测曾留下陈旧状态；现在持续输出 Enabled=false 和空端口数组。修正零端点时 Ports=[null]，新增状态清理断言。
- existing-session、multi-instance、fast-launcher 测试通过。三个脚本同步至安装目录，旧版保存在 backups/live-test-fixes-*；未构建安装包。
- 实机证据：../live-multi-test/verify-reopened.json、verify-video.json、verify-video-recovered-first.json、verify-installed-second.json；截图 ../previews/multi-test-foreground.png 和 multi-test-video.png。
- 当前原聊天进程 6828 无 remote-debugging-port，保留不重启。不能把两个测试实例通过等同于所有第三方启动入口兼容。
- 隔离测试监测及视频服务已停止；正式状态已启用，12911 和 12912 测试窗口由安装目录的监测管理。额外误开的同端口进程已清理。用户前台已恢复原聊天窗口。