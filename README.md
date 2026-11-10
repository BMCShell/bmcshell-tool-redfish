# BMCShell Redfish

对当前目标执行 Redfish 请求，支持 JSON 和请求体文件。 这是独立的 BMCShell 3.0 工具插件，基于本地 BMC Shell 2.22.0 发布仓的工具实现。

```bash
bmc plugin install --file .
bmc help tool redfish --usage
bmc use 192.0.2.10
redfish --auth
bmc tool redfish
```

工具随目标会话激活。系统依赖为 `curl`。代理由 `bmc proxy` 管理。发布时在本仓运行 `pwsh -File ./scripts/pack-release.ps1`，输出 ZIP 和 SHA256 清单。
