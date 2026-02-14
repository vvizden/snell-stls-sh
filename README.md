# snell-stls-sh：Snell v5 + ShadowTLS v3 一键部署脚本（Debian/Ubuntu + systemd）

Language: [中文](README.md) | [English](README.en.md)

## 免责声明

- 本项目仅用于个人学习和交流，请勿用于非法目的，请勿在生产环境中使用。
- 本项目不对可用性、安全性、长期可维护性做任何保证，你需要自行评估并承担风险。
- 脚本会从互联网下载并安装第三方软件（Snell / ShadowTLS）；请自行确认来源与使用许可，并确保遵守当地法律法规与服务商条款。

## 新手一键部署（这节看完就够了）

你需要准备：

- 一台 Debian/Ubuntu 的 VPS（必须有 `systemd`）
- 能登录 VPS 的账号（常见是 `root`）
- 你的本机有 `ssh`
- VPS 需要能访问 GitHub（出网正常），并安装了 `curl`

占位符说明：

- `<VPS_IP>`: 你的 VPS 公网 IP
- `<SSH_PORT>`: SSH 端口（默认 `22`，如果你没改过就可以不写 `-p/-P`）
- `<PRIVATE_KEY_PATH>`: 私钥路径（SSH Key 登录时，如果你的私钥不是默认位置才需要）

### 方式 A：SSH Key 登录（推荐）

说明：如果你的私钥就在默认位置（例如 `~/.ssh/id_ed25519`），通常不需要写 `-i`。

1) 登录 VPS（SSH 端口默认 22 时最简单，可省略 `-p`）：

```bash
ssh root@<VPS_IP>
```

如果你的私钥不在默认位置，加 `-i <PRIVATE_KEY_PATH>`：

```bash
ssh -i <PRIVATE_KEY_PATH> root@<VPS_IP>
```

如果你改过 SSH 端口（非 22），加 `-p <SSH_PORT>`：

```bash
ssh -p <SSH_PORT> root@<VPS_IP>
```

2) 在 VPS 上从 GitHub 下载脚本（默认下载 `main` 分支最新版本）：

```bash
apt-get update
apt-get install -y curl ca-certificates
curl -fsSL -o /root/deploy_snell_stls.sh https://raw.githubusercontent.com/vvizden/snell-stls-sh/main/deploy_snell_stls.sh
chmod +x /root/deploy_snell_stls.sh
```

提示：如果你希望“锁定版本”，可以把上面 URL 里的 `main` 替换为某个 commit hash。

3) 在 VPS 上执行无人值守一键部署：

```bash
bash /root/deploy_snell_stls.sh install --non-interactive --yes
```

如果你不是 `root` 登录，请用 `sudo`：

```bash
sudo bash /root/deploy_snell_stls.sh install --non-interactive --yes
```

### 方式 B：密码登录

说明：如果你的 VPS 禁用了密码登录（`PasswordAuthentication no`），这种方式不适用。

1) 登录 VPS（会提示输入密码）：

```bash
ssh root@<VPS_IP>
```

如果你改过 SSH 端口（非 22），加 `-p <SSH_PORT>`：

```bash
ssh -p <SSH_PORT> root@<VPS_IP>
```

如果你本机配置了很多密钥，导致一直优先尝试 Key 认证、迟迟不弹密码提示，可强制走密码认证：

```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no root@<VPS_IP>
```

如果你改过 SSH 端口（非 22），同时需要强制走密码认证：

```bash
ssh -p <SSH_PORT> -o PreferredAuthentications=password -o PubkeyAuthentication=no root@<VPS_IP>
```

2) 在 VPS 上从 GitHub 下载脚本：

```bash
apt-get update
apt-get install -y curl ca-certificates
curl -fsSL -o /root/deploy_snell_stls.sh https://raw.githubusercontent.com/vvizden/snell-stls-sh/main/deploy_snell_stls.sh
chmod +x /root/deploy_snell_stls.sh
```

3) 在 VPS 上执行无人值守一键部署：

```bash
bash /root/deploy_snell_stls.sh install --non-interactive --yes
```

### 部署完成后怎么拿 Surge 配置

部署成功后：

- 终端会直接输出一条可用于 Surge 的 `[Proxy]` 配置行（包含 Proxy Name，例如 `Snell-v5 = snell, ...`）
- 同时会生成可复制粘贴的片段文件：
  - `/root/snell-surge-proxy.conf`
  - `/root/snell-stls-info.txt`

你只需要复制终端里那条 `Snell-v5 = snell, ...`，或者执行下面命令查看文件并复制：

```bash
cat /root/snell-surge-proxy.conf
```

到这里，新手流程结束。后面内容只在你想自定义/排错时再看。

## 这个脚本做了什么（简版）

- 安装 `snell-server` 与 `shadow-tls` 二进制，并注册 `systemd` 服务
- `snell-server` 只监听本机回环：`127.0.0.1:<snell-port>`（默认 `18080`）
- `shadow-tls` 监听公网入口：`0.0.0.0:<public-port>`（默认 `443/tcp`）
- 会生成/修改的关键文件：
  - `/etc/snell/snell-server.conf`
  - `/etc/systemd/system/snell-server.service`
  - `/etc/systemd/system/shadow-tls.service`
  - `/usr/local/bin/snell-server`
  - `/usr/local/bin/shadow-tls`
  - `/root/snell-surge-proxy.conf`
  - `/root/snell-stls-info.txt`

注意：`/root/snell-surge-proxy.conf` 与 `/root/snell-stls-info.txt` 包含密钥信息，按“密码”对待，不要随意截图/转发。

## 常用命令（按需）

```bash
# 交互式安装（会提问并二次确认）
bash /root/deploy_snell_stls.sh install

# 升级（尽量保留现有端口/密钥/SNI）
bash /root/deploy_snell_stls.sh upgrade --yes

# 查看状态（服务状态、监听端口、最近日志）
bash /root/deploy_snell_stls.sh status

# 卸载（保留连接信息文件）
bash /root/deploy_snell_stls.sh uninstall --yes

# 卸载并清理连接信息文件
bash /root/deploy_snell_stls.sh uninstall --purge --yes
```

## 参数速览（按需）

| 参数 | 作用 | 默认值 | 你什么时候需要改 |
| --- | --- | --- | --- |
| `--public-port <port>` | 公网入口端口（客户端连这个） | `443` | 443 被占用，或你想换端口 |
| `--snell-port <port>` | Snell 本地端口（仅回环） | `18080` | 和你现有服务冲突时 |
| `--snell-psk <value>` | Snell PSK | 自动随机生成 | 多台机器要统一配置，或你要手动固定 |
| `--stls-password <value>` | ShadowTLS 密码 | 自动随机生成 | 同上 |
| `--stls-sni <domain>` | ShadowTLS 伪装域名（SNI） | 自动选择 | 自动选择失败，或你要指定 |
| `--ssh-port <port>` | 防火墙保活用的 SSH 端口 | 自动探测（失败则 `22`） | 你 SSH 不是常见端口且探测不准 |
| `--no-firewall` | 不自动改防火墙，只打印建议命令 | 关闭 | 你有自己的防火墙策略 |
| `--non-interactive` | 非交互（不提问） | 关闭 | 自动化/批量部署 |
| `--yes` | 跳过确认提示 | 关闭 | 自动化执行时 |

完整参数以脚本帮助为准：

```bash
bash /root/deploy_snell_stls.sh --help
```

## 排错（只保留和脚本直接相关的）

### 1) Snell 下载失败，提示“疑似被反爬/验证码页面替换”

脚本需要解析 Surge 的 Snell release notes 页面来定位 Linux 下载链接；如果你的 VPS 出口被拦或页面结构变化，会失败，并保存原始页面到：

```bash
sed -n '1,80p' /tmp/snell_release_notes_last.html
```

### 2) 服务启动失败 / 不是 active

优先用脚本自带命令看完整信息：

```bash
bash /root/deploy_snell_stls.sh status
```

### 3) 你手动指定的 `--stls-sni` 被脚本拒绝

脚本会用 `openssl s_client -tls1_3` 做 TLS1.3 探测；你提供的域名如果当前网络下无法完成 TLS1.3 握手，会直接报错退出。换一个支持 TLS1.3 的常见域名即可，或不传让脚本自动选。

## 参考资料（可选）

- Surge KB（Snell release notes）：<https://kb.nssurge.com/surge-knowledge-base/release-notes/snell>
- ShadowTLS 项目：<https://github.com/ihciah/shadow-tls>
