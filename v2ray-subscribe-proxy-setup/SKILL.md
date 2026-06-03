---
name: v2ray-subscribe-proxy-setup
category: devops
description: 从订阅链接解码配置 V2Ray 代理，处理 HTTP 伪装节点，测试并启动服务
---

# V2Ray 订阅代理配置技能

## 关键教训

### HTTP 伪装是常见陷阱
免费/低价订阅节点使用 **HTTP 伪装**（`type: http`），而非 TLS。错误配置为 TLS 会导致连接被重置。

**原始 VMess JSON 判断：**
```json
{ "type": "http", "net": "tcp", "host": "...", "path": "..." }
```

**V2Ray 5.x 正确配置：**
```json
{
  "streamSettings": {
    "network": "tcp",
    "tcpSettings": {
      "header": {
        "type": "http",
        "request": {
          "method": "GET",
          "path": ["/path"],
          "headers": { "Host": ["host.example.com"] }
        }
      }
    }
  }
}
```

**必须跳过：**
- `xhttp` 协议（V2Ray 5.x 不支持）
- IPv6 地址
- 信息节点（剩余流量、套餐到期、必看、防丢失等）

### 解码订阅
```python
decoded = base64.b64decode(subscription_text).decode()
links = re.findall(r'vmess://([A-Za-z0-9+/=]+)', decoded)
```

### Docker 拉取镜像需要代理
```json
// /etc/docker/daemon.json
{ "proxies": { "http-proxy": "socks5://127.0.0.1:10808", "https-proxy": "socks5://127.0.0.1:10808" } }
```
然后 `systemctl restart docker`

### 验证代理
```bash
curl -s --socks5 127.0.0.1:10808 --connect-timeout 8 https://httpbin.org/ip
```

出口 IP 非本机则正常。

## 常见故障排查

### 现象：curl 下载某个 HTTPS URL 超时，但 ping/dns 正常

**排查步骤（按顺序）：**

1. `curl -v --max-time 10 <URL>` — 看 HTTP 状态码和 `location` 响应头
2. 如果返回 **301/302**：检查 `location` 指向的域名（如 `raw.githubusercontent.com`），这个域名可能被直连封锁
3. 如果返回 **200 但极慢**：出口宽带限速或目标服务器限速
4. `curl -x http://127.0.0.1:10809 --max-time 10 <可疑域名>` — 通过代理测

**常见重定向场景：**
- `officecli.ai` → Cloudflare → 301 重定向到 `raw.githubusercontent.com`（GitHub）
- 订阅站/技能站使用 Cloudflare CDN，原始域名通但 GitHub Raw 不通

**解决：**
```bash
# 方法1：设置环境变量走代理
export https_proxy=http://127.0.0.1:10809
curl -fsSL <URL> -o <output>

# 方法2：内联指定
https_proxy=http://127.0.0.1:10809 curl -fsSL <URL>
```

### 快速诊断命令
```bash
# 快速检查域名直连是否通
curl -v --max-time 8 https://<domain> 2>&1 | grep -E '< HTTP|< location|< Content-Type'

# 快速检查域名走代理是否通
curl -x http://127.0.0.1:10809 --max-time 8 -s -o /dev/null -w "%{http_code}" https://<domain>
```

## 测试策略：两阶段筛选
1. **端口连通性初筛**：对所有节点 IP:PORT 做 socket 连接（3秒超时），过滤掉端口不通的节点
2. **V2Ray 实际连接测试**：对端口可达的节点逐一启动测试，curl 验证出口 IP

这种方法比直接测试所有节点快 3-5 倍，尤其在节点数量 >20 时效果明显。

## 订阅来源
- fffffl.v2ray.ws（当前使用）：https://ffff.v2ray.ws/api/subscribe?token=<token>&flag=1
  - 节点数量：30+，含美国 CN2 GIA 节点
  - 格式：base64 解码后含 vmess:// 和 info 节点（info 无 address 字段需跳过）

## 工作流程
1. 下载订阅 → `/tmp/v2ray_sub_<name>.txt`
2. Python 解码+解析（跳过 info 节点和 IPv6）
3. 端口初筛（socket 3秒超时）
4. V2Ray 逐一测试 + curl 验证出口 IP
5. leastPing 排序，写入 config.json
6. `systemctl enable --now v2ray`
7. 验证代理：`curl -s --socks5 127.0.0.1:10808 --connect-timeout 8 https://httpbin.org/ip`
8. Docker 配置代理后 `docker compose pull`
