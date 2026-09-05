# 贡献说明

[English](CONTRIBUTING.en.md)

项目使用 Bash 和 systemd，为 Debian / Ubuntu 上的 Snell 5.x / 6.x 提供版本管理，支持 amd64 和 aarch64。

## 修改要求

- 保持 `snell.sh` 独立可运行，并支持安全地加载函数用于测试。
- 保留完整版本号及 Beta / RC 后缀，分别记录安装版本和客户端协议版本。
- 通过所有权标记确定管理范围；升级与回滚应同步处理二进制、服务端配置、客户端配置和通道。
- 将密钥输出集中在 `export` 命令中。
- 功能和使用方式变化时，同步更新中英文文档。

## 验证与提交

按[测试说明](tests/README.md)运行语法检查、ShellCheck 和测试。部署逻辑变化时，补充真实 systemd 与 Surge 验证，并将环境、版本和结果记入[验证记录](VERIFICATION.md)。

提交说明请写清解决的问题、使用方式的变化及验证结果。
