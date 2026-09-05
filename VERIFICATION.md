# 验证记录

[English](VERIFICATION.en.md)

日期：2026-09-05。结果适用于下述环境和版本。

## 版本发现与支持范围

- 官方发布页发现的最新版本：stable 为 **5.0.1**，rc 和 beta 均为 **6.0.0rc2**。发现范围以页面所列链接为准。
- 测试时，指定版本 **6.0.0b4** 的官方文件仍可下载。
- 工具支持 **5.x 和 6.x**，包括后续 Beta、RC 和正式版。其他主版本需要更新管理工具。
- 官方 6.0.0rc2 / aarch64 二进制自报版本为 `snell-server v6.0.0 (Aug 7 2026)`。工具分别记录完整发布标签、二进制自报版本、来源地址和哈希；预发布版本允许省略后缀的自报结果，其他基础版本或冲突后缀会被拒绝。
- 测试文件采用 `local-only` 校验记录，本地哈希用于检测后续文件变化。

来源：[官方发布页](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)、[官方参数说明](https://manual.nssurge.com/policies/snell.html)。

## 自动化检查

- Bash 语法检查通过。
- `snell.sh` 的 ShellCheck 检查通过。
- macOS 的 6 组通用测试通过。
- Debian 12 / root 环境的 14 组测试通过，覆盖版本排序、RC 后缀回归、页面发现回退、通道筛选、缺失架构、输入校验、配置生成、部署事务、恢复失败记录保留、所有权、完整性、锁、校验值和暂存失败。

## 服务端验收

环境为 ARM Mac 上的 Docker Desktop，使用以 systemd 为 PID 1 的一次性特权容器。

| 系统与架构 | 测试版本 | 结果 |
| --- | --- | --- |
| Debian 12 / aarch64 | 5.0.1、6.0.0rc2、6.0.0b4 | 完整 systemd 验收通过 |
| Ubuntu 24.04.4 / aarch64 | 5.0.1、6.0.0rc2、6.0.0b4 | 完整 systemd 验收通过 |
| ARM 模拟执行的 Debian 12 / amd64 | 5.0.1 | 受阻：官方二进制以 root 或 snell 账号单独执行 `--version` 均出现段错误，工具在激活前拒绝安装 |

待完成：amd64 主机验收、主机或虚拟机启动、断电恢复、其他系统版本及长时间运行测试。

## Surge 验收

Surge Mac **6.9.0（12250）**，通过本机 TCP 端口映射连接 Debian / aarch64 容器：

- **6.0.0rc2**：导出配置检查通过；连续 3 次 HTTPS HEAD 请求返回 200，服务端观察到同一条 Snell TCP 连接；UDP 策略测试通过，延迟 2 ms。
- **回滚后的 5.0.1**：恢复的导出配置检查通过；连续 3 次 HTTPS HEAD 请求返回 200，沿用同一条 Snell TCP 连接；UDP 策略测试通过，延迟 1 ms。
- 临时策略已移除，原配置已恢复并重新加载。
- 本轮验证覆盖本机客户端互通及连接复用。公网可达性、生产可靠性、实时 UDP 性能和 Surge iOS 兼容性需单独验证。

复现步骤见[测试方法](tests/README.md)。
