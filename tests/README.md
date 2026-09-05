# 测试方法

[English](README.en.md)

在项目根目录执行以下命令。实际覆盖范围见[验证记录](../VERIFICATION.md)。

## 语法、版本解析与事务测试

```bash
bash -n snell.sh
bash tests/run.sh
docker build -f tests/Dockerfile -t snellctl-test .
docker run --rm snellctl-test bash -c 'shellcheck snell.sh && bash tests/run.sh'
```

macOS 运行 6 组通用测试，Linux / root 容器运行全部 14 组，覆盖文件所有权、哈希、链接切换和锁。这些测试模拟 systemd 和网络响应；服务端与 Surge 的实际运行按下述步骤验证。

## systemd 验收

请在专用测试主机或虚拟机上使用一次性容器。测试会创建账号、安装服务并清理部署数据，下载过程需要访问官方站点。

```bash
docker build --build-arg DISTRO=debian:12 -f tests/systemd.Dockerfile -t snellctl-systemd-test .
docker run -d --name snellctl-acceptance --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock snellctl-systemd-test
docker exec -e SNELLCTL_DISPOSABLE_TEST=YES snellctl-acceptance bash /src/tests/systemd-acceptance.sh
docker rm -f snellctl-acceptance
```

使用 `DISTRO=ubuntu:24.04` 重复测试，并分别在 amd64 和 aarch64 主机上验收。Docker 的 arm64 对应 Snell 的 aarch64。ARM Mac 上的 `--platform linux/amd64` 属于模拟执行，amd64 主机验收需单独完成。

脚本固定验证 `5.0.1 → 6.0.0rc2 → 6.0.0b4`，Beta 通道更新后应同步调整预期。测试覆盖端口占用、安装、权限、通道切换、降级、密钥保留、离线回滚、启动失败恢复、SIGTERM 中断恢复、未完成事务恢复、服务重启及卸载清理。故障注入集中在测试脚本中。系统重启与断电恢复需在虚拟机中另行验收。

## Surge 验收

准备独立的测试服务器或容器，将 TCP 端口映射到可访问的地址。安装目标版本后，私下获取 `snellctl export` 输出，添加为临时 Surge 策略。使用容器时，将导出内容的地址和端口替换为映射后的地址和端口。通过 `surge-cli --check <profile>` 检查配置后重新加载。

等待策略可用，再执行：

```bash
surge-cli http probe https://www.apple.com/library/test/success.html snellctl-acceptance
surge-cli test-policy-udp snellctl-acceptance
```

重复 HTTPS 请求，并检查服务端 `ss -Htn 'sport = :443'` 输出，观察是否沿用同一条 TCP 连接。回滚后，使用恢复的客户端配置重复测试。

测试完成后移除临时策略，恢复并重新加载原配置。导出内容和密钥应私下保存。公网可达性、生产路由、吞吐量和 iOS 兼容性需单独验证。
