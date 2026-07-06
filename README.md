# VPN Skills

Hermes Agent / Codex 的 VPN 相关技能集，覆盖 V2Ray 订阅配置、并发测速，以及本机 Mihomo 代理工作流。

## 包含技能

### v2ray-subscribe-proxy-setup
V2Ray 订阅链接解码、配置生成、HTTP 伪装节点处理、代理服务测试与启动。

**功能特性：**
- 自动解析订阅链接获取节点列表
- 解码 base64 编码的节点配置
- 处理 HTTP 伪装节点（VLESS/VMess + TCP HTTP header）
- 配置本地 HTTP/SOCKS 代理端口
- 验证节点可用性

**使用方法：**
在 Hermes Agent 中加载技能：
```text
/skill v2ray-subscribe-proxy-setup
```

### v2ray-concurrent-speedtest
从订阅获取节点、过滤网站在线节点、V2Ray 协议并发测速脚本。

**功能特性：**
- 并发测速（10 并发）
- 自动过滤失效节点
- 显示延迟与带宽
- 订阅 token 通过环境变量传入，不写入仓库

**使用方法：**
```bash
export V2RAY_SUBSCRIBE_TOKEN="<token>"
python3 ~/.hermes/skills/network/v2ray-concurrent-speedtest/scripts/speedtest.py
```

### vpn-mihomo-codex
Codex / Windows 本机 Mihomo 代理工作流，和 `dw-skills` 的网络故障规则对齐。

**功能特性：**
- 记录本地 Codex skill：`C:\Users\54711\.codex\skills\vpn-mihomo\SKILL.md`
- 只使用本地脚本里的单一订阅源；公共仓库只保存占位符
- 网络失败或高延迟时按需启动本地 Mihomo
- `start` 只启动本地端口，不启用 Windows 系统代理
- `start-global` 仅在用户明确要求全局/浏览器代理时使用
- 默认优先节点：`美国 a 顶级路线 负载均衡 x2`
- `prefer` 可对正在运行的 Mihomo 切换到默认优先节点
- 命令行优先使用当前 shell 的 `HTTP_PROXY` / `HTTPS_PROXY`
- 仅检查订阅时禁止启动代理或修改系统代理
- 禁止打印订阅 URL、节点服务器、UUID、密码、token 或完整配置

## 安全边界

- 订阅链接、token、UUID、密码、节点服务器和完整配置都视为 secrets。
- 仓库只保存技能说明和无密钥脚本模板，不保存真实订阅 URL 或 token。
- 只在 GitHub、包下载、外部 API、浏览器登录等联网任务失败或高延迟时启用代理。
- 纯订阅检查只允许拉取、解码、统计和配置校验，不启动代理、不改系统代理。
- 默认不启用 Windows 全局系统代理；只有在用户明确要求浏览器或系统应用走代理时才使用 `start-global`，任务结束后必须恢复。

## 文件结构

```text
vpn-skills/
├── v2ray-subscribe-proxy-setup/
│   └── SKILL.md
├── v2ray-concurrent-speedtest/
│   ├── SKILL.md
│   └── scripts/
│       └── speedtest.py
├── vpn-mihomo-codex/
│   ├── SKILL.md
│   └── scripts/
│       └── vpn-mihomo.ps1
├── .gitignore
└── README.md
```

## 环境要求

- V2Ray 测速路径：V2Ray 5.x、Python 3、curl。
- Codex/Mihomo 路径：Windows、Mihomo、PowerShell。
- 网络：能访问订阅服务器；如果直连失败，先按技能规则检查代理状态。

## 相关链接

- [V2Ray 项目](https://github.com/v2fly/v2ray-core)
- [Mihomo 项目](https://github.com/MetaCubeX/mihomo)
- [Hermes Agent](https://github.com/nousresearch/hermes-agent)

## License

MIT