# Hermes VPN Skills

Hermes Agent 的 VPN 相关技能集，包含 V2Ray 订阅配置与并发测速两个模块。

## 包含技能

### v2ray-subscribe-proxy-setup
V2Ray 订阅链接解码、配置生成、HTTP 伪装节点处理、代理服务测试与启动。

**功能特性：**
- 自动解析订阅链接获取节点列表
- 解码 base64 编码的节点配置
- 处理 HTTP 伪装节点（VLESS+TLS）
- 配置本地 HTTP/SOCKS 代理端口
- 验证节点可用性

**使用方法：**
在 Hermes Agent 中加载技能：
```
/skill v2ray-subscribe-proxy-setup
```

### v2ray-concurrent-speedtest
从订阅获取节点、过滤网站在线节点、V2Ray 协议并发测速脚本。

**功能特性：**
- 并发测速（10 并发）
- 自动过滤失效节点
- 显示延迟与带宽
- 支持台湾、韩国、日本等节点

**使用方法：**
```
python3 ~/.hermes/skills/network/v2ray-concurrent-speedtest/scripts/speedtest.py
```

## 文件结构

```
hermes-vpn-skills/
├── v2ray-subscribe-proxy-setup/
│   └── SKILL.md          # 订阅配置技能说明
├── v2ray-concurrent-speedtest/
│   ├── SKILL.md          # 测速技能说明
│   └── scripts/
│       └── speedtest.py  # 并发测速脚本
├── .gitignore
└── README.md
```

## 环境要求

- V2Ray 已安装 (`/usr/local/bin/v2ray`)
- Python 3.6+
- 网络：能访问订阅服务器

## 相关链接

- [V2Ray 项目](https://github.com/v2fly/v2ray-core)
- [Hermes Agent](https://github.com/nousresearch/hermes-agent)

## License

MIT