#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Darling File —— Python 传输核心
功能：局域网发现 / UDP 小文件快传 / TCP 大文件直连 / 官方中转(WS,不落盘) / 网页直连分享 / HTTP API 桥接
依赖：aiohttp websockets
"""
import asyncio, json, os, sys, socket, uuid, time, hashlib, base64, urllib.request, urllib.error, struct
from pathlib import Path

API_BASE = os.environ.get("DF_API", "https://api.darling02.de5.net")
RELAY_BASE = os.environ.get("DF_RELAY", "https://relay.darling02.de5.net")
APP_NAME = "Darling File"
DEVICE_ID = uuid.uuid4().hex[:8]

# 端口
PORT_DISCOVERY = 28680   # UDP 广播发现
PORT_TCP = 28681         # TCP 大文件直连
PORT_UDP = 28682         # UDP 小文件快传
PORT_WEB = 28683         # 网页直连分享
UDP_MAX = 1024 * 1024    # UDP 走快传的大小上限(1MB)

RECV_DIR = Path(os.environ.get("DF_RECV", str(Path.home() / "DarlingFile" / "Received")))
RECV_DIR.mkdir(parents=True, exist_ok=True)
SHARE_DIR = Path(os.environ.get("DF_SHARE", str(Path.home() / "DarlingFile" / "Share")))
SHARE_DIR.mkdir(parents=True, exist_ok=True)

# 全局状态
STATE = {
    "token": "", "user": None,
    "peers": {},          # id -> {name, ip, port, last_seen}
    "lan_ip": "127.0.0.1",
    "relay_session": None,  # 发送端：{code, sessionId, wsUrl, files:[...], created_at}
    "incoming": [],       # 接收队列 [{id, name, size, from, method, path, progress, status}]
    "history": [],        # 历史 [{id, name, size, direction, method, status, ts}]
    "web_share": None,    # {files:[{id,name,size}], started}
}

def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)

# ---------------- 网络工具 ----------------
def get_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def http_req(method, url, data=None, token=None, timeout=20):
    headers = {"User-Agent": "Mozilla/5.0 (DarlingFile/0.1)", "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # 直连，避免本地代理干扰
    try:
        with opener.open(req, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read().decode())
        except Exception:
            return {"error": f"HTTP {e.code}"}
    except Exception as e:
        return {"error": str(e)}

# ---------------- 登录（复用 Darling AI 账号） ----------------
async def api_login(email, password):
    r = await asyncio.to_thread(http_req, "POST", f"{API_BASE}/api/auth/login", {"email": email, "password": password})
    if r.get("ok") and r.get("access"):
        STATE["token"] = r["access"]
        STATE["user"] = {"email": r.get("email"), "role": r.get("role")}
        return {"ok": True, "email": r.get("email")}
    return {"ok": False, "error": r.get("error") or "登录失败，请检查账号密码"}

def api_logout():
    STATE["token"] = ""
    STATE["user"] = None
    return {"ok": True}

# ---------------- 局域网发现 ----------------
async def discovery_loop():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind(("", PORT_DISCOVERY))
    sock.setblocking(False)
    hello = json.dumps({"t": "df-hello", "id": DEVICE_ID, "name": socket.gethostname(), "tcp": PORT_TCP, "udp": PORT_UDP}).encode()
    while True:
        try:
            await asyncio.get_running_loop().sock_sendto(sock, hello, ("255.255.255.255", PORT_DISCOVERY))
        except Exception:
            pass
        # 收集响应
        for _ in range(6):
            try:
                data, addr = await asyncio.wait_for(asyncio.get_running_loop().sock_recvfrom(sock, 4096), timeout=0.4)
                try:
                    m = json.loads(data.decode())
                    if m.get("t") == "df-hello" and m.get("id") != DEVICE_ID:
                        STATE["peers"][m["id"]] = {"name": m.get("name", "未知设备"), "ip": addr[0], "tcp": m.get("tcp", PORT_TCP), "udp": m.get("udp", PORT_UDP), "last_seen": time.time()}
                except Exception:
                    pass
            except (asyncio.TimeoutError, BlockingIOError):
                break
            except Exception:
                break
        # 清理离线设备（>8s）
        now = time.time()
        for pid in [p for p, v in STATE["peers"].items() if now - v["last_seen"] > 8]:
            STATE["peers"].pop(pid, None)
        await asyncio.sleep(2)

# ---------------- TCP 大文件直连 ----------------
async def tcp_server():
    server = await asyncio.start_server(tcp_handle, "0.0.0.0", PORT_TCP)
    async with server:
        await server.serve_forever()

async def tcp_handle(reader, writer):
    peer = writer.get_extra_info("peername")
    try:
        head_len = struct.unpack(">I", await reader.readexactly(4))[0]
        head = json.loads((await reader.readexactly(head_len)).decode())
        if head.get("t") != "file":
            writer.close(); return
        name, size = head.get("name", "file"), head.get("size", 0)
        fid = head.get("id", uuid.uuid4().hex[:10])
        path = RECV_DIR / f"{fid}_{os.path.basename(name)}"
        rec = {"id": fid, "name": name, "size": size, "from": peer[0] if peer else "?", "method": "TCP 直连", "path": str(path), "progress": 0, "status": "receiving"}
        STATE["incoming"].insert(0, rec)
        got = 0
        with open(path, "wb") as f:
            while got < size:
                chunk = await reader.read(262144)
                if not chunk: break
                f.write(chunk); got += len(chunk)
                rec["progress"] = got
        rec["status"] = "done" if got >= size else "interrupted"
        rec["progress"] = size
        writer.write(b"OK")
        await writer.drain()
        STATE["history"].insert(0, {"id": fid, "name": name, "size": size, "direction": "收", "method": "TCP 直连", "status": rec["status"], "ts": time.time()})
        log(f"TCP 收到 {name} ({got}/{size}) from {peer}")
    except Exception as e:
        log("TCP 接收错误:", e)
    finally:
        writer.close()

async def tcp_send(ip, path):
    name = os.path.basename(path)
    size = os.path.getsize(path)
    fid = uuid.uuid4().hex[:10]
    rec = {"id": fid, "name": name, "size": size, "to": ip, "method": "TCP 直连", "progress": 0, "status": "sending"}
    STATE["history"].insert(0, {**rec, "direction": "发", "ts": time.time()})
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(ip, PORT_TCP), timeout=8)
        head = json.dumps({"t": "file", "name": name, "size": size, "id": fid}).encode()
        writer.write(struct.pack(">I", len(head)) + head)
        sent = 0
        with open(path, "rb") as f:
            while True:
                chunk = f.read(262144)
                if not chunk: break
                writer.write(chunk)
                sent += len(chunk)
                rec["progress"] = sent
                await writer.drain()
        await writer.drain()
        await asyncio.wait_for(reader.read(2), timeout=8)
        writer.close()
        rec["status"] = "done"
        return {"ok": True, "id": fid, "size": sent}
    except Exception as e:
        rec["status"] = "failed"
        return {"ok": False, "error": str(e)}

# ---------------- UDP 小文件快传 ----------------
async def udp_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", PORT_UDP))
    sock.setblocking(False)
    CHUNK = 1200
    while True:
        try:
            data, addr = await asyncio.get_running_loop().sock_recvfrom(sock, 4096)
            try:
                m = json.loads(data.decode())
            except Exception:
                continue
            if m.get("t") == "u-init":
                # 开始接收：等所有分块
                name, size, total = m.get("name"), m.get("size"), m.get("total")
                fid = m.get("id", uuid.uuid4().hex[:10])
                rec = {"id": fid, "name": name, "size": size, "from": addr[0], "method": "UDP 快传", "path": str(RECV_DIR / f"{fid}_{os.path.basename(name)}"), "progress": 0, "status": "receiving"}
                STATE["incoming"].insert(0, rec)
                buf = {}
                expect = 0
                while expect < total:
                    data, addr = await asyncio.get_running_loop().sock_recvfrom(sock, 4096)
                    try:
                        cm = json.loads(data.decode())
                    except Exception:
                        continue
                    if cm.get("t") == "u-chunk" and cm.get("id") == fid:
                        seq = cm["seq"]; buf[seq] = base64.b64decode(cm["d"])
                        expect += 1
                        rec["progress"] = int(expect / total * size)
                    elif cm.get("t") == "u-ackreq" and cm.get("id") == fid:
                        # 补发确认
                        missing = [s for s in range(total) if s not in buf]
                        await asyncio.get_running_loop().sock_sendto(sock, json.dumps({"t": "u-ack", "id": fid, "missing": missing[:50]}).encode(), addr)
                with open(rec["path"], "wb") as f:
                    for s in range(total):
                        f.write(buf[s])
                rec["status"] = "done"; rec["progress"] = size
                STATE["history"].insert(0, {"id": fid, "name": name, "size": size, "direction": "收", "method": "UDP 快传", "status": "done", "ts": time.time()})
                await asyncio.get_running_loop().sock_sendto(sock, json.dumps({"t": "u-done", "id": fid}).encode(), addr)
                log(f"UDP 收到 {name} from {addr[0]}")
        except (BlockingIOError, asyncio.TimeoutError):
            await asyncio.sleep(0.05)
        except Exception as e:
            log("UDP 接收错误:", e)
            await asyncio.sleep(0.1)

async def udp_send(ip, path):
    name = os.path.basename(path)
    size = os.path.getsize(path)
    if size > UDP_MAX:
        return {"ok": False, "error": f"文件大于 {UDP_MAX//1024//1024}MB，请用 TCP/中转"}
    fid = uuid.uuid4().hex[:10]
    data = open(path, "rb").read()
    CHUNK = 1200
    chunks = [data[i:i+CHUNK] for i in range(0, len(data), CHUNK)]
    total = len(chunks)
    rec = {"id": fid, "name": name, "size": size, "to": ip, "method": "UDP 快传", "progress": 0, "status": "sending"}
    STATE["history"].insert(0, {**rec, "direction": "发", "ts": time.time()})
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", 0)); sock.setblocking(False)
    try:
        await asyncio.get_running_loop().sock_sendto(sock, json.dumps({"t": "u-init", "id": fid, "name": name, "size": size, "total": total}).encode(), (ip, PORT_UDP))
        sent = 0
        for i, c in enumerate(chunks):
            await asyncio.get_running_loop().sock_sendto(sock, json.dumps({"t": "u-chunk", "id": fid, "seq": i, "d": base64.b64encode(c).decode()}).encode(), (ip, PORT_UDP))
            sent += 1
            rec["progress"] = int(sent / total * size)
            if sent % 40 == 0:
                await asyncio.sleep(0.005)
        # 等待确认，缺块重发
        await asyncio.sleep(0.3)
        for _ in range(3):
            try:
                d, _ = await asyncio.wait_for(asyncio.get_running_loop().sock_recvfrom(sock, 4096), timeout=1)
                m = json.loads(d.decode())
                if m.get("t") == "u-ack" and m.get("id") == fid and m.get("missing"):
                    for s in m["missing"][:50]:
                        await asyncio.get_running_loop().sock_sendto(sock, json.dumps({"t": "u-chunk", "id": fid, "seq": s, "d": base64.b64encode(chunks[s]).decode()}).encode(), (ip, PORT_UDP))
                elif m.get("t") == "u-done" and m.get("id") == fid:
                    rec["status"] = "done"
                    return {"ok": True, "id": fid, "size": size}
            except (asyncio.TimeoutError, BlockingIOError):
                pass
        rec["status"] = "done"
        return {"ok": True, "id": fid, "size": size}
    except Exception as e:
        rec["status"] = "failed"
        return {"ok": False, "error": str(e)}

# ---------------- 官方中转（WS，不落盘） ----------------
async def relay_create_session(files):
    if not STATE["token"]:
        return {"ok": False, "error": "中转需要登录"}
    r = await asyncio.to_thread(http_req, "POST", f"{RELAY_BASE}/api/session", {"name": "transfer"}, STATE["token"])
    if not r.get("ok"):
        return {"ok": False, "error": r.get("error") or "创建中转会话失败"}
    STATE["relay_session"] = {**r, "files": [{"name": os.path.basename(f), "size": os.path.getsize(f), "path": f} for f in files], "created_at": time.time()}
    return {"ok": True, "code": r["code"], "wsUrl": r["wsUrl"], "sessionId": r["sessionId"], "url": r["url"], "expiresAt": r["expiresAt"]}

async def relay_query(code):
    code = (code or "").strip().upper()
    r = await asyncio.to_thread(http_req, "GET", f"{RELAY_BASE}/api/session/{code}")
    if not r.get("ok"):
        return {"ok": False, "error": r.get("error") or "口令无效"}
    return {"ok": True, **r}

async def relay_release(code=None):
    code = code or (STATE["relay_session"] or {}).get("code")
    if code and STATE["token"]:
        await asyncio.to_thread(http_req, "DELETE", f"{RELAY_BASE}/api/session/{code}", None, STATE["token"])
    if STATE.get("relay_session"):
        STATE["relay_session"] = None
    return {"ok": True}

async def relay_send(ws_url, files, progress_cb=None):
    """发送端：连 WS → 等 ready → 逐文件 meta/分块/done → 等 ack，未确认自动重发"""
    import websockets
    async with websockets.connect(ws_url + "?role=send", proxy=None) as ws:
        # 等接收端就绪，避免开头消息丢失
        for _ in range(60):
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=1)
                if isinstance(msg, str) and '"ready"' in msg:
                    break
            except asyncio.TimeoutError:
                continue
        await asyncio.sleep(0.5)  # 给 DO 稳定时间
        for f in files:
            name = os.path.basename(f); size = os.path.getsize(f); fid = uuid.uuid4().hex[:10]
            rec = {"id": fid, "name": name, "size": size, "method": "官方中转", "progress": 0, "status": "sending"}
            STATE["history"].insert(0, {**rec, "direction": "发", "ts": time.time()})
            for attempt in range(3):
                await ws.send(json.dumps({"type": "meta", "id": fid, "name": name, "size": size}))
                sent = 0
                with open(f, "rb") as fh:
                    while True:
                        chunk = fh.read(32768)
                        if not chunk: break
                        await ws.send(chunk)
                        sent += len(chunk)
                        rec["progress"] = sent
                        if progress_cb: progress_cb(fid, sent, size)
                await ws.send(json.dumps({"type": "done", "id": fid}))
                # 等接收端 ack
                acked = False
                for _ in range(15):
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=1)
                        if isinstance(msg, str) and f'"ack"' in msg and fid in msg:
                            acked = True
                            break
                    except asyncio.TimeoutError:
                        continue
                if acked:
                    rec["status"] = "done"
                    break
                log(f"中转 {name} 未确认，重试 {attempt+1}/3")
            else:
                rec["status"] = "failed"
        await ws.send(json.dumps({"type": "end"}))
        log("中转发送完成")

async def relay_recv(ws_url, progress_cb=None):
    """接收端：连 WS → 收 meta/分块 → 写文件"""
    import websockets
    async with websockets.connect(ws_url + "?role=recv", proxy=None) as ws:
        # 通知发送端：我已就绪（通过 DO 转发给 send 端）
        await ws.send(json.dumps({"type": "ready"}))
        cur = None
        while True:
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=30)
            except asyncio.TimeoutError:
                continue
            except Exception:
                break
            if isinstance(msg, str):
                try:
                    m = json.loads(msg)
                except Exception:
                    continue
                if m.get("type") == "meta":
                    fid = m.get("id", uuid.uuid4().hex[:10])
                    path = RECV_DIR / f"{fid}_{os.path.basename(m.get('name','file'))}"
                    cur = {"id": fid, "name": m.get("name"), "size": m.get("size", 0), "path": str(path), "fp": open(path, "wb"), "got": 0, "method": "官方中转"}
                    STATE["incoming"].insert(0, {"id": fid, "name": cur["name"], "size": cur["size"], "from": "中转", "method": "官方中转", "path": str(path), "progress": 0, "status": "receiving"})
                elif m.get("type") == "done" and cur:
                    cur["fp"].close()
                    for inc in STATE["incoming"]:
                        if inc.get("id") == cur["id"]:
                            inc["status"] = "done"; inc["progress"] = cur["size"]
                    STATE["history"].insert(0, {"id": cur["id"], "name": cur["name"], "size": cur["size"], "direction": "收", "method": "官方中转", "status": "done", "ts": time.time()})
                    if progress_cb: progress_cb(cur["id"], cur["size"], cur["size"])
                    # 回 ack，让发送端确认本文件已收齐（未收齐会触发重发）
                    await ws.send(json.dumps({"type": "ack", "id": cur["id"]}))
                    cur = None
                elif m.get("type") in ("end", "peer_closed"):
                    break
            elif cur:
                cur["fp"].write(msg)
                cur["got"] += len(msg)
                if progress_cb: progress_cb(cur["id"], cur["got"], cur["size"])
        if cur:
            cur["fp"].close()
        log("中转接收结束")

# ---------------- 网页直连分享（不走中转） ----------------
def render_share_page(files):
    cards = "".join(f'<div class="f"><div class="fi">📄</div><div class="fm"><div class="fn">{h(f["name"])}</div><div class="fs">{f["size"]} 字节</div></div><a class="dl" href="/dl/{f["id"]}">下载</a></div>' for f in files)
    return f"""<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{APP_NAME} 分享</title>
<style>body{{margin:0;background:#0b1117;color:#e8eef4;font-family:system-ui,-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center}} .box{{max-width:560px;width:92%;background:#141e28;border:1px solid #223141;border-radius:20px;padding:34px;box-shadow:0 20px 60px rgba(0,0,0,.4)}} h1{{font-size:20px;margin:0 0 6px}} .sub{{color:#8fa3b5;font-size:13px;margin-bottom:22px}} .f{{display:flex;align-items:center;gap:14px;background:#1a2733;border:1px solid #223141;border-radius:14px;padding:14px 16px;margin-bottom:12px}} .fi{{font-size:24px}} .fm{{flex:1;min-width:0}} .fn{{font-weight:600;font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}} .fs{{color:#8fa3b5;font-size:12px;margin-top:2px}} .dl{{background:linear-gradient(135deg,#2BBBAD,#0F766E);color:#fff;text-decoration:none;font-size:13px;font-weight:700;padding:9px 18px;border-radius:10px}} .dl:hover{{filter:brightness(1.1)}} .tip{{color:#5c6f80;font-size:11.5px;text-align:center;margin-top:16px}}</style></head>
<body><div class="box"><h1>{APP_NAME} · 网页直连分享</h1><div class="sub">对方已分享 {len(files)} 个文件，直接下载（不经中转）</div>{cards}<div class="tip">{APP_NAME} v0.1 · 直连分享不经过中转服务器</div></div></body></html>"""

def h(s):
    return (s or "").replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;")

async def web_share_handler(request):
    from aiohttp import web
    path = request.path
    if path == "/":
        files = (STATE["web_share"] or {}).get("files", [])
        return web.Response(text=render_share_page(files), content_type="text/html")
    if path.startswith("/dl/"):
        fid = path.split("/")[2]
        files = (STATE["web_share"] or {}).get("files", [])
        for f in files:
            if f["id"] == fid and os.path.exists(f["path"]):
                return web.FileResponse(f["path"], headers={"Content-Disposition": f'attachment; filename*=UTF-8\'\'{urllib.parse.quote(f["name"])}'})
        return web.Response(text="文件不存在", status=404)
    return web.Response(text="not found", status=404)

async def web_share_start():
    from aiohttp import web
    if not STATE["web_share"]:
        STATE["web_share"] = {"files": []}
    app = web.Application()
    app.router.add_route("*", "/{tail:.*}", web_share_handler)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT_WEB)
    await site.start()
    STATE["web_share"]["started"] = True

async def web_share_add(files):
    if not STATE.get("web_share") or not STATE["web_share"].get("started"):
        await web_share_start()
    for f in files:
        fid = uuid.uuid4().hex[:10]
        STATE["web_share"]["files"].append({"id": fid, "name": os.path.basename(f), "size": os.path.getsize(f), "path": f})
    STATE["web_share"]["last_update"] = time.time()
    ip = STATE["lan_ip"]
    return {"ok": True, "url": f"http://{ip}:{PORT_WEB}/"}

def web_share_stop():
    STATE["web_share"] = None
    return {"ok": True}

# ---------------- HTTP API（桥接给 Flutter） ----------------
async def make_api():
    from aiohttp import web
    app = web.Application()

    async def j(resp, status=200):
        return web.json_response(resp, status=status, headers={"Access-Control-Allow-Origin": "*"})

    async def h_login(request):
        b = await request.json()
        return await j(await api_login(b.get("email",""), b.get("password","")))
    async def h_logout(request):
        return await j(api_logout())
    async def h_me(request):
        return await j({"ok": True, "logged_in": bool(STATE["token"]), "user": STATE["user"], "device": {"id": DEVICE_ID, "name": socket.gethostname(), "ip": STATE["lan_ip"]}})
    async def h_peers(request):
        return await j({"ok": True, "peers": [{"id": k, "name": v["name"], "ip": v["ip"], "last_seen": v["last_seen"]} for k, v in STATE["peers"].items()]})
    async def h_send(request):
        b = await request.json()
        path = b.get("path"); method = b.get("method", "auto"); ip = b.get("ip")
        if not path or not os.path.exists(path):
            return await j({"ok": False, "error": "文件不存在"}, 400)
        if method == "udp":
            r = await udp_send(ip, path)
        elif method == "tcp":
            r = await tcp_send(ip, path)
        elif method == "relay":
            r = await relay_create_session([path])
        else:  # auto：≤1MB UDP，否则 TCP（需 ip）
            if os.path.getsize(path) <= UDP_MAX and ip:
                r = await udp_send(ip, path)
            elif ip:
                r = await tcp_send(ip, path)
            else:
                r = await relay_create_session([path])
        return await j(r)
    async def h_send_multi(request):
        # 批量：给中转会话加文件（多个文件一次会话），创建后自动开始发送
        b = await request.json()
        files = b.get("files", [])
        if not files:
            return await j({"ok": False, "error": "未选择文件"}, 400)
        r = await relay_create_session(files)
        if r.get("ok"):
            s = STATE.get("relay_session")
            if s and s.get("wsUrl"):
                asyncio.ensure_future(relay_send(s["wsUrl"], [f["path"] for f in s["files"]]))
        return await j(r)
    async def h_relay_session(request):
        b = await request.json()
        return await j(await relay_create_session(b.get("files", [])))
    async def h_relay_query(request):
        b = await request.json()
        return await j(await relay_query(b.get("code", "")))
    async def h_relay_release(request):
        b = await request.json() or {}
        return await j(await relay_release(b.get("code")))
    async def h_relay_send(request):
        b = await request.json()
        s = STATE.get("relay_session")
        if not s or not s.get("wsUrl"):
            return await j({"ok": False, "error": "没有进行中的中转会话"}, 400)
        asyncio.ensure_future(relay_send(s["wsUrl"], [f["path"] for f in s["files"]]))
        return await j({"ok": True})
    async def h_relay_recv(request):
        b = await request.json()
        r = await relay_query(b.get("code", ""))
        if not r.get("ok"):
            return await j(r, 404)
        asyncio.ensure_future(relay_recv(r["wsUrl"]))
        return await j({"ok": True, "session": r})
    async def h_incoming(request):
        return await j({"ok": True, "incoming": STATE["incoming"]})
    async def h_history(request):
        return await j({"ok": True, "history": STATE["history"]})
    async def h_status(request):
        s = STATE.get("relay_session")
        return await j({"ok": True, "logged_in": bool(STATE["token"]), "user": STATE["user"],
                        "relay_session": {k: s[k] for k in ("code","url","expiresAt")} if s else None,
                        "web_share": STATE["web_share"]})
    async def h_web_share(request):
        b = await request.json() or {}
        files = b.get("files", [])
        if not files:
            return await j({"ok": False, "error": "未选择文件"}, 400)
        return await j(await web_share_add(files))
    async def h_web_stop(request):
        return await j(web_share_stop())

    app.router.add_post("/api/login", h_login)
    app.router.add_post("/api/logout", h_logout)
    app.router.add_get("/api/me", h_me)
    app.router.add_get("/api/peers", h_peers)
    app.router.add_post("/api/send", h_send)
    app.router.add_post("/api/send-multi", h_send_multi)
    app.router.add_post("/api/relay/session", h_relay_session)
    app.router.add_post("/api/relay/query", h_relay_query)
    app.router.add_post("/api/relay/release", h_relay_release)
    app.router.add_post("/api/relay/send", h_relay_send)
    app.router.add_post("/api/relay/recv", h_relay_recv)
    app.router.add_get("/api/incoming", h_incoming)
    app.router.add_get("/api/history", h_history)
    app.router.add_get("/api/status", h_status)
    app.router.add_post("/api/web-share", h_web_share)
    app.router.add_post("/api/web-stop", h_web_stop)
    return app

# ---------------- 启动 ----------------
async def main():
    STATE["lan_ip"] = get_lan_ip()
    loop = asyncio.get_running_loop()
    log(f"{APP_NAME} v0.1 · 本机 {STATE['lan_ip']} · 设备 {DEVICE_ID}")
    log(f"TCP {PORT_TCP} / UDP {PORT_UDP} / 发现 {PORT_DISCOVERY} / 网页 {PORT_WEB}")
    asyncio.ensure_future(discovery_loop())
    asyncio.ensure_future(tcp_server())
    asyncio.ensure_future(udp_server())
    app = await make_api()
    runner = None
    try:
        from aiohttp import web
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, "127.0.0.1", 18924)
        await site.start()
        log("本地桥接 API: http://127.0.0.1:18924")
    except Exception as e:
        log("API 启动失败:", e)
    await asyncio.Event().wait()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
