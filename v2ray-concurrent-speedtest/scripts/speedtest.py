#!/usr/bin/env python3
"""V2Ray并发测速脚本
流程：订阅更新 → 比对网站在线节点 → 过滤IPv6 → 并发V2Ray协议测速
"""
import socket, re, base64, json, time, threading, subprocess, os

V2RAY_BIN = "/usr/local/bin/v2ray"
LOCAL_SOCKS = 40808
TEST_URL = "https://speed.cloudflare.com/__down?bytes=1000000"
TIMEOUT = 10
MAX_CONCURRENT = 10

# === 1. 从订阅获取节点 ===
def fetch_subscription():
    token = "8a93d9fe998043beaf748aedc3102e26"
    url = f"https://ffff.v2ray.ws/api/subscribe?token={token}&flag=1"
    import urllib.request
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
            if n.get('add') != '127.0.0.1' and n.get('type') != 'info':
                nodes.append(n)
        except:
            pass
    return nodes

# === 2. 网站在线节点名（从HTML提取，硬编码避免额外依赖）===
WEBSITE_ONLINE_NAMES = {
    "香港 福利福利福利节点 x1 (如无法使用请更新订阅)",
    "香港1 x2", "香港 Plus A x2", "香港 Plus B x2",
    "香港 Plus Max A x2", "香港 Plus Max B x2",
    "日本 Plus S1", "日本 Plus C x2", "日本 Plus F x2",
    "日本 Plus G x2", "日本 Plus H x2",
    "台湾 1", "瑞典 1", "日本 TTTT2", "韩国_1",
    "美国 z 顶级路线 负载均衡 x2", "美国 a 顶级路线 负载均衡 x2",
    "美国 b1 CN2 GIA 顶级路线 x4", "美国 b2 CN2 GIA 顶级路线 x4",
    "美国 b3 CN2 GIA 顶级路线 x4", "美国 b4 CN2 GIA 顶级路线 x4",
    "美国 b6 CN2 GIA 顶级路线 x4", "美国 b7 CN2 GIA 顶级路线 x4",
    "美国 b8 CN2 GIA 顶级路线 x4", "美国 b9 CN2 GIA 顶级路线 x4",
    "美国 b10 CN2 GIA 顶级路线 x4", "美国 b11 CN2 GIA 顶级路线 x4",
    "美国 a-j 负载均衡 动态ip",
}

# === 3. 过滤节点 ===
def filter_nodes(nodes):
    filtered, skip_ipv6, skip_offline = [], [], []
    for n in nodes:
        name = n.get('ps', '')
        addr = n.get('add', '')
        if ':' in addr:  # IPv6
            skip_ipv6.append(name)
            continue
        if name not in WEBSITE_ONLINE_NAMES:
            skip_offline.append(name)
            continue
        filtered.append(n)
    return filtered, skip_ipv6, skip_offline

# === 4. 构建单节点配置 ===
def build_config(node, port):
    host = node.get('host', '')
    path = node.get('path', '/')
    return {
        "log": {"loglevel": "error"},
        "inbounds": [{"port": port, "listen": "127.0.0.1", "protocol": "socks"}],
        "outbounds": [{
            "protocol": "vmess",
            "settings": {
                "vnext": [{
                    "address": node['add'], "port": int(node['port']),
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
                            "path": [path],
                            "headers": {"Host": [host] if host else [node['add']]}
                        }
                    }
                }
            }
        }]
    }

# === 5. 测速worker ===
def test_node(node, idx, results, sem):
    name = node.get('ps', node['add'])
    port = LOCAL_SOCKS + idx
    cfg = f"/tmp/vt_{os.getpid()}_{idx}.json"
    try:
        with open(cfg, 'w') as f:
            json.dump(build_config(node, port), f)
        proc = subprocess.Popen([V2RAY_BIN, "run", "-c", cfg],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.8)
        if proc.poll() is not None:
            results[name] = ('FAIL', 0, 0, 'start_fail')
            os.unlink(cfg); sem.release(); return
        try:
            start = time.time()
            r = subprocess.run(
                ['curl', '-s', '--proxy', f'socks5://127.0.0.1:{port}',
                 '--connect-timeout', str(TIMEOUT), '-o', '/dev/null',
                 '-w', '%{http_code}|%{speed_download}', TEST_URL],
                capture_output=True, text=True, timeout=TIMEOUT + 3)
            elapsed = time.time() - start
            parts = r.stdout.strip().split('|')
            code = int(parts[0]) if parts else 0
            speed = int(parts[1]) if len(parts) > 1 else 0
            if code == 200 and speed > 0:
                results[name] = ('OK', round(elapsed * 1000), speed // 1024, f'{speed // 1024}KB/s')
            else:
                results[name] = ('FAIL', 0, 0, f'http{code}')
        finally:
            proc.terminate()
            try: proc.wait(timeout=3)
            except: proc.kill()
        os.unlink(cfg)
    except Exception as e:
        results[name] = ('FAIL', 0, 0, str(e)[:30])
    finally:
        sem.release()

# === 6. 主流程 ===
def main():
    print("=== 1. 获取订阅 ===")
    nodes = fetch_subscription()
    print(f"订阅共 {len(nodes)} 个节点")

    print("\n=== 2. 过滤（网站在线 - IPv6）===")
    filtered, skip_ipv6, skip_offline = filter_nodes(nodes)
    print(f"测速节点: {len(filtered)}")
    if skip_ipv6:
        print(f"  跳过IPv6: {len(skip_ipv6)}")
    if skip_offline:
        print(f"  跳过非在线: {len(skip_offline)}")

    print(f"\n=== 3. 并发测速 ({MAX_CONCURRENT}并发, URL: {TEST_URL}) ===")
    results = {}
    sem = threading.Semaphore(MAX_CONCURRENT)
    threads = []
    t0 = time.time()

    for i, node in enumerate(filtered):
        sem.acquire()
        t = threading.Thread(target=test_node, args=(node, i, results, sem))
        t.start()
        threads.append(t)

    for t in threads:
        t.join()
    elapsed = time.time() - t0

    ok = sorted([(n, d) for n, d in results.items() if d[0] == 'OK'],
                key=lambda x: x[1][2], reverse=True)
    fail = [(n, d) for n, d in results.items() if d[0] == 'FAIL']

    print(f"\n{'='*70}")
    print(f"测速完成！耗时 {elapsed:.1f}s | 可用 {len(ok)}/{len(filtered)}")
    print(f"{'='*70}")
    print(f"{'节点':<40} {'延迟(ms)':>10} {'速度(KB/s)':>12}")
    print(f"{'-'*70}")
    for n, (s, lat, speed, _) in ok:
        print(f"{n:<40} {lat:>10.0f} {speed:>12,}")

    if fail:
        print(f"\n不可用 ({len(fail)}):")
        for n, (s, _, _, e) in fail:
            print(f"  {n}: {e}")

    if ok:
        print(f"\n最优: {ok[0][0]} ({ok[0][1][2]:,} KB/s)")

if __name__ == "__main__":
    main()
