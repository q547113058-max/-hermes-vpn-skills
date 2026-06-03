---
name: v2ray-concurrent-speedtest
description: V2Ray并发测速脚本 - 从订阅获取节点，过滤网站在线节点，并发V2Ray协议测速
---
# V2Ray 并发测速

## 功能
从订阅地址获取节点，过滤网站显示的在线节点，并发 V2Ray 协议测速（10线程，~15秒测完28节点）

## 依赖
- `/usr/local/bin/v2ray` (V2Ray 5.x)
- `curl` (SOCKS5 代理支持)
- Python 3

## 测速 URL
```
https://speed.cloudflare.com/__down?bytes=1000000
```

## V2Ray 单节点测试配置格式（V2Ray 5.x）

关键教训：不能加 routing 规则，否则 DNS 走 Facebook 导致超时。

```python
config = {
    "log": {"loglevel": "error"},
    "inbounds": [{"port": PORT, "listen": "127.0.0.1", "protocol": "socks"}],
    "outbounds": [{
        "protocol": "vmess",
        "settings": {
            "vnext": [{
                "address": node['add'],
                "port": int(node['port']),
                "users": [{"id": node['id'], "alterId": int(node.get('aid', 0)), "security": "auto"}]
            }]
        },
        "streamSettings": {
            "network": "tcp",
            "tcpSettings": {
                "header": {
                    "type": "http",
                    "request": {
                        "method": "GET",
                        "path": [node.get('path', '/')],
                        "headers": {"Host": [node.get('host', node['add'])]}
                    }
                }
            }
        }
    }]
}
```

## 并发测速架构

- 每个节点一个 V2Ray 子进程 + 独立端口（base_port + 线程索引）
- 等待 0.8 秒让 V2Ray 启动
- curl 通过 `--proxy socks5://127.0.0.1:PORT` 测速
- `threading.Semaphore(MAX_CONCURRENT)` 控制并发数
- 超时 TIMEOUT=10 秒

## 订阅解码

```python
import base64, re, json, urllib.request

def fetch_subscription(token):
    url = f"https://ffff.v2ray.ws/api/subscribe?token={token}&flag=1"
    req = urllib.request.Request(url, headers={"User-Agent": "v2rayN"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = resp.read()
    decoded = base64.b64decode(raw).decode('utf-8', errors='replace')
    positions = [m.start() for m in re.finditer('vmess://', decoded)]
    nodes = []
    for i, pos in enumerate(positions):
        b64 = decoded[pos+8:positions[i+1] if i+1 < len(positions) else None].split('\n')[0].strip()
        try:
            n = json.loads(base64.b64decode(b64).decode('utf-8'))
            if n.get('add') != '127.0.0.1' and n.get('type') != 'info' and ':' not in n.get('add',''):
                nodes.append(n)
        except: pass
    return nodes
```

## 已知在线节点名（从网页HTML提取）

```python
WEBSITE_ONLINE_NAMES = {
    "香港 福利福利福利节点 x1 (如无法使用请更新订阅)",
    "香港1 x2", "香港 Plus A x2", "香港 Plus B x2",
    "香港 Plus Max A x2", "香港 Plus Max B x2",
    "日本 Plus S1", "日本 Plus C x2", "日本 Plus F x2",
    "日本 Plus G x2", "日本 Plus H x2",
    "台湾 1", "瑞典 1", "日本 TTTT2", "韩国_1",
    "美国 z 顶级路线 负载均衡 x2", "美国 a 顶级路线 负载均衡 x2",
    "美国 b1-b11 CN2 GIA 顶级路线 x4",
    "美国 a-j 负载均衡 动态ip",
}
```

## 典型结果

- 28 节点测速：15 秒完成（10并发）
- 可用率：26/28
- 最优：香港 1 x2（2,165 KB/s）
- 次优：日本 Plus 系列（1,300–1,700 KB/s）
- 美国 CN2 GIA：630–670 KB/s

## 踩坑记录

1. **V2Ray 5.x routing 导致 DNS 污染**：routing 规则里的 domainStrategy/DNS 会让所有域名走 Facebook DNS → 超时。解决：单节点测试不加 routing。
2. **IPv6 节点**：本机不支持 IPv6 必须跳过（`:` in add）
3. **订阅 Token**：ffff.v2ray.ws 的 token 从网站用户资料页获取
4. **urllib 不支持 SOCKS5**：必须用 curl 或 socks 库
5. **V2Ray 启动时间**：需要等 0.8 秒再发请求
