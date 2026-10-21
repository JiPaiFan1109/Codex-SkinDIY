# 启动延迟优化与接手审计（2026-10-21）

接手对话：`01a15cc0-6f15-7b51-8eaa-e8cade72875e`。工作入口为 `current/`，本轮修改现按用户要求命名为 **1.2.0（待发布）**，等待与其他改动一起上传。审计基于 1.1.1 源码完成。本机安装 VERSION 重新核对为 1.1.0；没有覆盖安装文件、重启 Codex、修改用户壁纸库或发布版本。

## 结论

重复打开时的主要延迟有可验证的改善方案：加快连接归属查询，并在 Codex 的浏览器存储中保留一个已校验的视频，避免每次通过 CDP 重传约 96 MiB 的媒体。首次使用新视频、缓存被清理或存储不可用时仍要完整传输，不能承诺所有启动都在一秒内完成。

本机只读记录显示，用户此次 Codex 主进程于北京时间 13:32:32 创建，多窗口监视器的注入进程于 13:32:43 创建。注入日志最后写入为 13:33:13；日志没有逐阶段时间，不能把这些差值全部归因于单一函数。

## 实现

- `engine/scripts/common-windows.ps1`：使用 Windows 原生 IPv4/IPv6 TCP owner 表查询监听端口，用进程对象读取可执行路径，移除该校验路径中的 NetTCPIP/CIM 开销。仍在 CDP 握手前后重新核对所有监听者，不缓存端口归属，不接受通配地址或错误进程。
- `engine/scripts/video-cache.mjs`、`video-blob.mjs`：缓存仅存当前一个视频，受既有 128 MiB 输入上限约束。按内容大小和 SHA-256 复用，与服务端口、随机令牌无关；读取时重新计算哈希。缓存损坏、权限/配额错误或超过 2 秒读取预算时回退原下载路径。暂停、页面替换、超时后的迟到结果不会挂载到新页面。缓存键采用保留的 `.invalid` 域名，仅作为 Cache API 标识，不产生网络请求。
- 保留上个对话的有效改动：多个窗口共享同一视频下载；本地视频服务使用流管道处理断连/文件读取异常，并拒绝错误 URL。
- 已撤回本轮尝试但未显示稳定收益的传输块大小、并行传输和解码改动，原有分块上传流程保留。
- 正式界面没有变化。`skin-manager.ps1`、`skin-manager.xaml` 的 SHA-256 与发布包完全相同。修正了继承自旧版的导航标签、圆形应用按钮测试断言，以及按钮测试未创建图片输出目录的问题。

原生查询依据：[GetExtendedTcpTable](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable)、[IPv6 owner row](https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcp6row_owner_pid)。

## 测量

连接校验：分别用发布包和修改后源码启动独立 Windows PowerShell 进程，对当前 Codex 连接进行只读校验，三次均返回已验证。

| 同一进程内调用 | 发布包 | 修改后 |
| --- | ---: | ---: |
| 第一次（包含原生查询初始化） | 4523 ms | 845 ms |
| 第二次 | 2101 ms | 76 ms |
| 第三次 | 3057 ms | 70 ms |

视频测试：启动独立无界面的 Edge 118，使用专用临时浏览器资料目录和本地测试页。只读加载用户当前视频（100,434,516 字节），不操作用户浏览器或壁纸库。挂载函数等待视频 `loadeddata`，解码宽度为 1920。第二次及重启后的测试改变服务令牌，并让 Node 下载函数直接报错，确保实际命中了浏览器磁盘缓存。

| 场景 | 加载至首帧 |
| --- | ---: |
| 首次完整校验、上传、解码 | 12,425 ms |
| 页面重新打开，读取缓存 | 461 ms |
| 浏览器完全退出并重新启动，读取缓存 | 647 ms |

以上不是 Codex 从启动到显示背景的端到端时间；不包含 Codex 自身启动、监视器发现等待及真实应用首屏负载。本机 Codex 仅做了只读能力检查：安全上下文、WebCrypto 和 Cache API 可访问。真实安装后的完整启动仍待验收。

## 回归结果

- 最终完整 Node 测试：46/46 通过。
- 修改后针对连接、快速恢复、快速应用、多实例、进程复用、启动后备、恢复及 UI 夹具的 15 个 Windows 脚本通过，其中 12 个记录在 `targeted-final.json`，另 3 个为 `coexistence-policy.tests.ps1`、`stale-process.tests.ps1`、`launch-argument-fallback.tests.ps1`。
- 接手时的 53 脚本批次初次为 49 通过、4 失败。导航/窗口比例两项属于过时 UI 断言，已修正；媒体测试单独重跑通过，原失败为全局操作锁争用；壁纸升级测试补齐带 LICENSE 的固定 Node runtime 参数后，临时目录内两次安装/升级通过。四项均已有通过记录。
- `button-states.ps1` 的正常、悬停、按下、禁用状态通过。未把这些单元检查当成人工视觉验收。
- 未运行会生成正式发布包或接管真实窗口的完整 `test:windows` 总入口。没有新发行包、安装实机验收或发布结论。

## 证据与下一步

原始证据在根目录 `.local-evidence/audit-20261021/`：

- `connection-before.json`、`connection-after.json`
- `video-cache-real-media.log`、`video-cache-browser-benchmark.log`
- `video-transfer-benchmark.mjs`（隔离浏览器与真实媒体可重复测试）
- `node-final.log`、`targeted-final.json`、`final-*.log`
- `windows-results-final.json`、`rerun-*.log`

后续若用户要求应用到本机，先备份已安装文件，再部署这四个运行时文件（`common-windows.ps1`、`video-blob.mjs`、`video-cache.mjs`、`video-server.mjs`），并验证实际 Codex 冷启动及再次启动。不能仅复制 `video-blob.mjs` 而漏掉新增依赖。发布版本需另行获准并完成构建/安装验证。
