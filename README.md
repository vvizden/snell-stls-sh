# snellctl：原生 Snell 单实例版本管理器

[English](README.en.md)

Bash + systemd，支持 Snell 5.x / 6.x 的正式版、RC、Beta 和指定版本。全新安装，一个服务，完整快照回滚。没有 ShadowTLS、SNI、后台更新、内核调优或自动防火墙修改。

> 本项目会从官方站点下载并运行第三方 Snell 二进制。测试版可能改变协议；服务端启动正常不等于 Surge 客户端兼容。项目按现状提供，不承诺可用性或抗干扰效果。

## 安装

要求：Debian/Ubuntu、运行中的 systemd、root/sudo、amd64 或 aarch64。按需通过 apt 安装 curl、CA 证书、unzip、jq、file、OpenSSL、util-linux、iproute2 等依赖。

在 VPS 下载脚本，检查后执行：

```bash
curl -fsSL -o snell.sh https://raw.githubusercontent.com/vvizden/snellctl/main/snell.sh
sudo bash snell.sh install
```

交互式安装询问公网 IPv4/域名、端口和通道。默认端口 443、通道 stable。可将下载 URL 中的 main 替换为已审阅的提交号，固定管理工具版本。

无人值守安装（将地址替换成自己的 VPS 公网 IPv4 或域名）：

```bash
sudo bash snell.sh install --server vpn.example.com --channel stable --non-interactive --yes
sudo snellctl status
sudo snellctl export
```

export 输出包含 PSK 的 Surge [Proxy] 配置行，不要放进公开日志、截图或 issue。普通安装/升级输出不打印密钥。自行在主机防火墙和云安全组放行所选 **TCP** 端口；脚本不修改 SSH 规则。

脚本不迁移旧项目、不接管其他工具的服务或账号、不停止占用端口的进程。检测到旧安装时，请先手工处理。保留下载的 snell.sh，以便卸载管理命令后清理剩余数据。

## 版本与命令

通道是**允许的成熟度上限**：

| 通道 | 允许版本 |
| --- | --- |
| stable | 正式版 |
| rc | 正式版 + RC |
| beta | 正式版 + RC + Beta |

先比较基础版本，再比较阶段和编号：`6.0.0b4 < 6.0.0rc < 6.0.0rc2 < 6.0.0 < 6.1.0b1`。无编号 rc 按 rc1 排序，但保留官方下载文件的拼写。Beta 通道会自然跟进 RC 和正式版。

```bash
snellctl versions
sudo snellctl upgrade --yes
sudo snellctl upgrade --channel rc --yes
sudo snellctl upgrade --channel beta --yes
sudo snellctl upgrade --version 6.0.0b4 --allow-downgrade --yes
sudo snellctl rollback --yes
sudo snellctl status
sudo snellctl export
```

--channel 和 --version 互斥。精确版本首次安装会保存对应通道；升级时指定精确版本不改变原通道。--allow-downgrade 仅允许与 upgrade --version 一起使用；切换通道也不隐式降级。rollback 无需联网，恢复上一套快照及其通道；再次 rollback 可切回。

实时读取官方 Markdown 发布页，提取失败时尝试同一页面的 HTML。versions 展示页面可发现版本和可读取的本地快照，不是完整历史目录。指定历史版本验证对应官方文件，不猜测相邻版本、不使用第三方镜像。页面滞后时无法发现尚未列出的新版本，可用 --version 指定已公布且仍可下载的文件。

先确定最新候选，再检查架构；缺包时停止，不静默选择旧版。未知版本格式停止发现，未知主版本要求更新管理工具；5.x/6.x 内的新版本无需逐一加入白名单。upgrade 只更新 Snell 服务端，不自行更新管理脚本。

## 运行默认值与边界

- IPv4 监听 0.0.0.0:443、IPv4 出站、系统 DNS。首次安装可用 --port 改端口。
- PSK 默认生成 32 字节随机数，保存为 64 位十六进制，升级保留。首次安装可用 --psk 指定 16–255 位 ASCII 字母、数字、下划线或连字符。
- 5.x 输出 version=5，6.x 输出 version=6；均为 reuse=true、block-quic=on，不默认启用 TFO。
- v6 使用内建默认加密/流量整形，不提供 unsafe-raw，也不向早期 Beta 写入新参数。
- 普通 UDP 经 Snell TCP 连接转发；客户端阻止 QUIC，无需开放公网 UDP 端口。TCP 传输仍会影响实时 UDP 性能。
- 唯一常驻服务 snell-server.service 使用专用 snell 账号，仅授予 CAP_NET_BIND_SERVICE；没有 root 身份或防火墙管理权限。
- /usr/local/sbin/snellctl 是安装后的入口。/opt/snellctl/generations/ 保存完整部署，current 原子链接指向当前快照。
- 快照包含二进制、服务端配置、Surge 片段及元数据。密钥配置仅 root/服务账号可读，客户端片段及元数据仅 root 可读。快照由工具管理，手动修改会被完整性检查拒绝。
- 下载限于官方 dl.nssurge.com/snell/。若同 URL 加 .sha256 的官方校验文件存在则核验；404/410 时记录 local-only。本地 SHA-256 用于检测后续变化，不是来源认证；来源认证依赖 HTTPS。

## 升级、恢复和卸载

下载、ZIP 检查、架构与可执行性检查完成后，才停止旧服务。事务记录旧状态，原子切换完整快照；随后在约十五秒窗口内检查目标进程连续五次（约四秒）保持运行且拥有正确监听端口。失败恢复旧二进制、配置、客户端片段和通道，并返回失败。只保留当前和上一套快照。

正常退出/信号尝试恢复未完成事务。强制终止或断电后，下一次有权限的管理操作先恢复或报告阻碍；回滚也失败时保留事务。systemd 开机使用当前完整快照，未完成更新不视为已经验收。单实例更新会短暂断开现有连接，不承诺无缝切换。

**启动检查不能验证公网防火墙、目标可达性或 Surge 协议兼容。** 更新后请在匹配的 Surge 上验证 HTTPS、连接复用和普通 UDP。需要时离线 rollback 并重新复制旧配置。普通 status 不打印密钥；分享 journal 日志前仍应自行检查。

```bash
sudo journalctl -u snell-server.service -n 50
sudo snellctl uninstall --yes
# 管理命令已删除，使用保存的脚本清理数据：
sudo bash snell.sh uninstall --purge --yes
```

默认卸载删除服务与命令，保留快照、密钥和账号。--purge 删除保留内容。保留数据时不能重新全新安装，需先显式 purge。陌生文件、账号变更、外部 systemd override 或所有权异常会要求手工检查。

## 验证

必须区分：官方页面发现的版本、工具支持的 5.x/6.x 范围、实际测试过的 OS/架构/版本。

```bash
bash -n snell.sh
bash tests/run.sh
docker build -f tests/Dockerfile -t snellctl-test .
docker run --rm snellctl-test
```

[测试说明](tests/README.md)记录真实 systemd 隔离验收方法。[VERIFICATION.md](VERIFICATION.md)记录本次实际验证覆盖。语法检查与 mock 测试不能替代真实 systemd 或 Surge 端连接验证。

## 官方资料

- [Snell 发布与安全说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
- [Surge Snell 参数](https://manual.nssurge.com/policies/snell.html)
- [Snell v6 设计说明](https://nssurge.com/blog/snell-v6/)

Snell 不提供前向保密，本工具不会改变协议安全属性。请根据自己的网络与安全需求选择。
