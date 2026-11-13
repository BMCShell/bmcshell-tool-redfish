# BMCShell Redfish

扩展包名 `bmcshell-tool-redfish`。

对当前目标执行 Redfish 请求，支持 JSON 和请求体文件。 这是独立的 BMCShell 3.0 工具插件，基于本地 BMC Shell 2.22.0 发布仓的工具实现。

```bash
bmc plugin install --file .
bmc tool redfish --help
bmc use 192.0.2.10
redfish --auth
redfish --help
```

工具随目标会话激活。系统依赖为 `curl`。代理由 `bmc proxy` 管理。发布时在本仓运行 `pwsh -File ./scripts/pack-release.ps1`，输出 `bmcshell-tool-redfish@<version>.zip` 和 SHA256 清单。

Redfish 请求继承框架的 TLS 证书校验设置 `BMCSHELL_TLS_MODE`。使用 `redfish --auth --tls-verify` 或 `redfish --auth --tls-insecure` 可以覆盖当前会话的设置，`redfish --auth` 恢复继承框架设置。

`bmc setting` 的「插件设置 → 工具 → redfish」可以设置连接超时、请求超时和 CA 证书文件。超时默认分别为 5 秒和 15 秒，允许 1 至 999 秒。开启证书校验时，curl 使用设置的 PEM 证书文件，留空时使用默认信任配置。已有的 `BMC_CONNECT_TIMEOUT`、`BMC_HTTP_TIMEOUT` 和 `BMC_CA_BUNDLE` 环境变量优先。

```bash
bmc setting --set plugin.bmcshell-tool-redfish.connect_timeout 10
bmc setting --set plugin.bmcshell-tool-redfish.request_timeout 30 --reload
```
