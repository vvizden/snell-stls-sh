# snellctl

[English](README.en.md)

轻量的 Snell 服务端管理工具，基于 Bash 和 systemd。支持 Snell 5.x / 6.x 的正式版、RC、Beta 和指定版本，提供安装、升级、回滚及 Surge 配置导出。

## 免责声明

本项目仅用于个人学习与交流，按现状提供。请自行评估使用风险，并遵守所在地法律法规及服务商的使用条款。作者不对使用本项目产生的损失承担责任。

## 安装

准备一台 Debian 或 Ubuntu 服务器，使用 systemd，架构为 amd64 或 aarch64，并具备 root 或 sudo 权限。本工具用于全新安装；已有 Snell 部署时，请先手动清理。

通过 SSH 登录服务器后，下载并检查脚本，再执行安装。以 root 登录时，可去掉命令中的 `sudo`。

```bash
sudo apt-get update
sudo apt-get install -y curl ca-certificates
curl -fsSL -o snell.sh https://raw.githubusercontent.com/vvizden/snellctl/main/snell.sh
sudo bash snell.sh install
```

按提示填写：

| 项目 | 填写内容 |
| --- | --- |
| 公网地址 | 服务器的公网 IPv4，或解析到它的域名 |
| 端口 | 默认 `443`，也可选择其他空闲端口 |
| 通道 | 推荐使用默认的 `stable` 正式版通道 |

其余依赖和密钥由脚本自动准备。安装后，请在服务器防火墙和云平台安全组中放行所选 **TCP 端口**。保留下载的 `snell.sh`，便于后续清理安装数据。

## 导入 Surge

在服务器上执行：

```bash
sudo snellctl export
```

将输出的配置行复制到 Surge 配置文件的 `[Proxy]` 段，保存后选择该节点并测试访问。导出内容包含连接密钥，请妥善保管。

## 日常使用

以下命令均在服务器上执行：

| 操作 | 命令 |
| --- | --- |
| 查看运行状态 | `sudo snellctl status` |
| 查看可用版本 | `snellctl versions` |
| 升级到当前通道的最新版本 | `sudo snellctl upgrade` |
| 更新 snellctl 工具本身 | `sudo snellctl self-update` |
| 恢复上一套部署 | `sudo snellctl rollback` |
| 导出当前 Surge 配置 | `sudo snellctl export` |
| 查看最近日志 | `sudo journalctl -u snell-server.service -n 50` |

升级保留连接密钥，会短暂中断连接。新版本启动检查失败时，工具会尝试恢复旧部署。升级后，请用 Surge 实际测试；需要恢复时执行 `rollback`，再导出并更新客户端配置。

`self-update` 从本项目 `main` 分支更新 `/usr/local/sbin/snellctl`，不重启 Snell，也不修改配置或回滚数据。下载或校验失败时保留原工具；无人值守执行时添加 `--yes`。旧版工具若不支持此命令，按安装步骤重新下载脚本后执行 `sudo bash snell.sh self-update`。

## 选择版本

手动执行升级时，工具从[官方发布页](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)选择通道内最新版本。

| 通道 | 候选范围 |
| --- | --- |
| `stable` | 正式版，推荐日常使用 |
| `rc` | 仅 RC 候选版 |
| `beta` | 仅 Beta 测试版 |

例如，切换到 RC 通道：

```bash
sudo snellctl upgrade --channel rc
```

各通道只选择自身类型的最新版本，不会混用；通道内没有可用版本时会报错。使用测试版前，请确认 Surge 客户端支持对应版本。

需要指定版本时，用 `--version` 替代 `--channel`；降级时加上 `--allow-downgrade`，例如：

```bash
sudo snellctl upgrade --version 5.0.1 --allow-downgrade
```

首次安装指定版本时，工具保存该版本对应的通道；升级时指定版本则沿用已保存的通道。完整参数见 `snellctl --help`。

## 卸载

卸载服务和管理命令，并永久删除配置、密钥、回滚数据及服务账户：

```bash
sudo snellctl uninstall
```

执行前会要求确认。卸载后可重新安装，无需保留安装脚本。

## 开发与反馈

[贡献说明](CONTRIBUTING.md) · [测试方法](tests/README.md) · [验证记录](VERIFICATION.md) · [安全反馈](SECURITY.md)
