---
name: vpn-mihomo-codex
category: network
description: Codex/Windows 本机 Mihomo VPN 工作流；网络失败或高延迟时启动本地 Mihomo，默认不接管 Windows 系统代理
---

# Codex Mihomo VPN 工作流

本技能用于把 `dw-skills` 的网络故障处理规则同步到 Hermes VPN 技能仓库。它描述本机 Codex 环境里的 Mihomo 使用边界，不包含真实订阅链接或节点凭据。

## 本地 Codex 技能

- Skill：`C:\Users\54711\.codex\skills\vpn-mihomo\SKILL.md`
- 脚本：`C:\Users\54711\.codex\skills\vpn-mihomo\scripts\vpn-mihomo.ps1`
- 公开模板：`vpn-mihomo-codex/scripts/vpn-mihomo.ps1`
- 本地混合代理：`127.0.0.1:17890`
- 本地控制端口：`127.0.0.1:19090`
- 当前偏好节点：`美国 a 顶级路线 负载均衡 x2`
- 订阅源策略：本地只使用脚本里的单一内置订阅 URL；公共仓库只能保存占位符，不能保存真实 URL/token
- `check` 动作：只拉取订阅、转换配置、执行 `mihomo -t`，不启动代理、不改系统代理
- `start` 动作：启动本地 Mihomo 端口，不启用 Windows 系统代理
- `start-global` 动作：只有用户明确要求浏览器/全局系统流量走代理时才使用
- `prefer` 动作：对正在运行的 Mihomo 切换 `PROXY` 分组到偏好节点

不要把本地脚本原样上传到公共仓库，因为脚本里可能包含订阅 URL 或 token。

## 触发条件

当以下联网任务出现超时、DNS 错误、连接失败或明显高延迟时，可以启用该流程：

- GitHub push/fetch/API 访问
- 包下载、依赖安装、镜像拉取
- 外部 API、OpenAI、Google、浏览器登录
- 需要稳定外网的自动化任务

## 工作流

1. 先确认任务确实需要外网访问，并记录失败命令或现象。
2. 运行状态检查，不直接改系统代理：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\54711\.codex\skills\vpn-mihomo\scripts\vpn-mihomo.ps1" status
```

订阅/配置检查使用：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\54711\.codex\skills\vpn-mihomo\scripts\vpn-mihomo.ps1" check
```

3. 如需继续联网任务，启动本地 Mihomo、切换偏好节点并测试：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\54711\.codex\skills\vpn-mihomo\scripts\vpn-mihomo.ps1" start
powershell -ExecutionPolicy Bypass -File "C:\Users\54711\.codex\skills\vpn-mihomo\scripts\vpn-mihomo.ps1" prefer
powershell -ExecutionPolicy Bypass -File "C:\Users\54711\.codex\skills\vpn-mihomo\scripts\vpn-mihomo.ps1" test
```

4. 命令行任务优先只在当前 shell 设置代理：

```powershell
$env:HTTP_PROXY="http://127.0.0.1:17890"
$env:HTTPS_PROXY="http://127.0.0.1:17890"
```

5. 任务结束后，如果本次启用了本地 Mihomo，停止或恢复原状态：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\54711\.codex\skills\vpn-mihomo\scripts\vpn-mihomo.ps1" stop
```

## 订阅检查边界

仅检查订阅或配置有效性时，只允许：

- 拉取本地脚本里的单一订阅 URL
- 解码 base64/V2Ray 订阅
- 统计节点数量和协议类型
- 校验是否是 Clash/Mihomo YAML 或 V2Ray 订阅格式，并在本地转换后运行 `mihomo -t`

禁止：

- 使用其它订阅 URL 或环境变量覆盖订阅源
- 启动代理进程
- 修改 Windows 系统代理
- 设置全局代理环境变量
- 打印订阅 URL、token、节点服务器、UUID、密码或完整配置

## 验证输出

报告时只输出安全摘要，例如：

```text
Fetch: OK
Format: base64-subscription
Nodes: 46
Protocols: vless=13, vmess=33
MihomoConfigTest: PASS
SystemProxyChanged: false
PreferredNode: 美国 a 顶级路线 负载均衡 x2
```

## 和 dw-skills 的关系

该技能与 `dw-skills` 中的“网络故障与 VPN 配方”保持一致：网络任务失败时可启用可用节点；订阅检查时不启动代理、不改系统代理、不暴露 secrets。默认使用本地 Mihomo 端口和命令级代理，只有明确要求浏览器或系统应用走代理时才使用 `start-global`。