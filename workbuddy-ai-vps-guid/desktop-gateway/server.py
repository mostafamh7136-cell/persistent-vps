#!/usr/bin/env python3
import os, base64, asyncio, secrets, json
from pathlib import Path
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.responses import JSONResponse, RedirectResponse, FileResponse
from fastapi.staticfiles import StaticFiles
import websockets

APP_DIR = Path("/opt/desktop-gw")
NOVNC_DIR = APP_DIR / "novnc"
APP_DIR.mkdir(parents=True, exist_ok=True)

# Authentication Configuration (UTF-8 Arabic support)
_AUTH_USER = os.environ.get("GATEWAY_USER", "admin")
_AUTH_PASS = os.environ.get("GATEWAY_PASS", "سيرفر_سحابي_آمن@13")
_AUTH_REALM = "Debian 13 Cloud Desktop - Protected Area"

# Build expected Basic Auth header in UTF-8
_RAW_PAIR = f"{_AUTH_USER}:{_AUTH_PASS}".encode("utf-8")
_VALID_AUTH = "Basic " + base64.b64encode(_RAW_PAIR).decode("ascii")

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

def _unauth():
    return JSONResponse(
        status_code=401,
        content={"detail": "Authentication required"},
        headers={"WWW-Authenticate": f'Basic realm="{_AUTH_REALM}", charset="UTF-8"'},
    )

def _check(req: Request) -> bool:
    auth = req.headers.get("Authorization", "")
    if not auth:
        return False
    # Standard digest comparison
    if secrets.compare_digest(auth.strip(), _VALID_AUTH):
        return True
    if "," in auth:
        return any(secrets.compare_digest(p.strip(), _VALID_AUTH) for p in auth.split(","))
    return False

@app.middleware("http")
async def auth_gate(request: Request, call_next):
    if request.url.path in ("/healthz", "/favicon.ico"):
        return await call_next(request)
    if not _check(request):
        return _unauth()
    return await call_next(request)

@app.get("/healthz")
async def healthz():
    return {"ok": True, "service": "secure-desktop-gateway", "auth": "basic"}

@app.get("/")
async def root():
    # resize=remote：桌面分辨率跟随浏览器窗口（Xtigervnc AcceptSetDesktopSize 默认开启），
    # 因此画面铺满整个浏览器，不会出现黑边；reconnect=1 让断线自动重连而不重建会话。
    return RedirectResponse(
        url="/desktop/vnc.html?autoconnect=1&resize=remote&reconnect=1"
            "&reconnect_delay=1000&path=websockify",
        status_code=302,
    )

@app.get("/scale")
async def root_scale():
    """备用入口：等比缩放（不请求改分辨率），用于不支持 remote resize 的场景"""
    return RedirectResponse(
        url="/desktop/vnc.html?autoconnect=1&resize=scale&path=websockify",
        status_code=302,
    )

@app.get("/snapshot.tar.gz")
async def snapshot_download():
    """认证保护的系统快照下载（由中间件强制 Basic Auth）"""
    f = Path("/backup/repo/snapshot.tar.gz")
    if not f.exists():
        return JSONResponse(status_code=404, content={"detail": "snapshot not ready"})
    return FileResponse(str(f), media_type="application/gzip", filename="snapshot.tar.gz")

@app.get("/snapshot.sha256")
async def snapshot_checksum():
    f = Path("/backup/repo/snapshot.sha256")
    if not f.exists():
        return JSONResponse(status_code=404, content={"detail": "checksum not ready"})
    return FileResponse(str(f), media_type="text/plain", filename="snapshot.sha256")

# ============ SSH over WebSocket 隧道（强制 Basic Auth）============
def _ws_auth_ok(ws: WebSocket) -> bool:
    auth = ws.headers.get("Authorization", "")
    if not auth:
        return False
    if secrets.compare_digest(auth.strip(), _VALID_AUTH):
        return True
    if "," in auth:
        return any(secrets.compare_digest(p.strip(), _VALID_AUTH) for p in auth.split(","))
    return False

@app.websocket("/ssh")
async def ssh_tunnel(ws: WebSocket):
    """WebSocket -> 127.0.0.1:22 二进制隧道。必须携带有效 Basic Auth 头。"""
    if not _ws_auth_ok(ws):
        await ws.close(code=4401, reason="Authentication required")
        return
    await ws.accept()
    reader = writer = None
    try:
        reader, writer = await asyncio.open_connection("127.0.0.1", 22)
        async def c2s():
            try:
                async for msg in ws.iter_bytes():
                    writer.write(msg)
                    await writer.drain()
            except Exception:
                pass
            finally:
                try: writer.close()
                except Exception: pass
        async def s2c():
            try:
                while True:
                    data = await reader.read(65536)
                    if not data:
                        break
                    await ws.send_bytes(data)
            except Exception:
                pass
            finally:
                try: await ws.close()
                except Exception: pass
        await asyncio.gather(c2s(), s2c())
    except WebSocketDisconnect:
        pass
    except Exception as e:
        try: await ws.close(code=1011, reason=str(e)[:120])
        except Exception: pass
    finally:
        if writer:
            try: writer.close()
            except Exception: pass

@app.get("/ssh/id_ed25519")
async def ssh_key_download():
    """认证保护的 SSH 私钥下载（Basic Auth 由中间件强制）"""
    f = Path("/workspace/debian13-server/ssh/id_ed25519")
    if not f.exists():
        return JSONResponse(status_code=404, content={"detail": "key not ready"})
    return FileResponse(str(f), media_type="application/octet-stream", filename="id_ed25519")

# ============ MCP (Model Context Protocol) — 严格受控 ============
import subprocess, shlex

_MCP_SERVER_INFO = {"name": "debian13-system-mcp", "version": "1.0.0"}
_MCP_PROTOCOL_VERSION = "2025-03-26"

# 允许浏览/读取的根目录（路径沙箱，符号链接解析后仍必须在白名单内）
_MCP_FS_ROOTS = ["/workspace/debian13-server", "/backup/repo"]
# 允许执行的无参数只读命令（精确匹配，shell=False）
_MCP_SAFE_CMDS = {"uptime", "df -h", "free -h", "date", "hostname", "ss -tln"}

def _mcp_path_ok(p: str) -> bool:
    try:
        rp = os.path.realpath(p)
        return any(rp == r or rp.startswith(r + "/") for r in _MCP_FS_ROOTS)
    except Exception:
        return False

def _mcp_tool_system_health() -> str:
    def on(cmd): return subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0
    # 注意：不能在 uvicorn 单线程事件循环内向自己的 6080 发 HTTP 请求（会自锁超时）。
    # 改为非阻塞读取 /proc/net/tcp 判断监听端口是否存在（端口 6080 = 十六进制 17C0）。
    def port_listening(port: int) -> bool:
        try:
            hexp = f"{port:04X}"
            with open("/proc/net/tcp", "r") as f:
                for line in f.readlines()[1:]:
                    cols = line.split()
                    if len(cols) > 3 and cols[3] == "0A" and cols[1].endswith(":" + hexp):
                        return True
            return False
        except Exception:
            return False
    gw = port_listening(6080)
    lines = {
        "Xtigervnc": on(["pgrep", "-x", "Xtigervnc"]),
        "xfce4-session": on(["pgrep", "-x", "xfce4-session"]),
        "websockify": on(["pgrep", "-x", "websockify"]),
        "sshd": on(["pgrep", "-x", "sshd"]),
        "gateway_6080": gw,
    }
    up = subprocess.run(["uptime"], capture_output=True, text=True, timeout=5).stdout.strip()
    df = subprocess.run(["df", "-h", "/"], capture_output=True, text=True, timeout=5).stdout.strip().splitlines()[-1]
    return "components: " + ", ".join(f"{k}={'OK' if v else 'DOWN'}" for k, v in lines.items()) + f"\nuptime: {up}\ndisk: {df}"

def _mcp_tool_snapshot_latest() -> str:
    repo = Path("/backup/repo")
    out = {}
    sha = repo / "snapshot.sha256"
    snap = repo / "snapshot.tar.gz"
    if sha.exists(): out["sha256"] = sha.read_text().split()[0]
    if snap.exists():
        st = snap.stat()
        out["size_bytes"] = st.st_size
        out["mtime"] = __import__("datetime").datetime.fromtimestamp(st.st_mtime).isoformat()
    try:
        out["last_commits"] = subprocess.run(
            ["git", "-C", str(repo), "log", "--oneline", "-3"],
            capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception as e:
        out["last_commits"] = f"unavailable: {e}"
    return json.dumps(out, indent=2, ensure_ascii=False)

def _mcp_tool_list_dir(path: str) -> str:
    if not _mcp_path_ok(path):
        return "ERROR: path outside allowed roots " + str(_MCP_FS_ROOTS)
    if not os.path.isdir(path):
        return "ERROR: not a directory"
    entries = sorted(os.listdir(path))[:200]
    return "\n".join(entries) if entries else "(empty)"

def _mcp_tool_read_file(path: str) -> str:
    if not _mcp_path_ok(path):
        return "ERROR: path outside allowed roots " + str(_MCP_FS_ROOTS)
    if not os.path.isfile(path):
        return "ERROR: not a file"
    if os.path.getsize(path) > 65536:
        return "ERROR: file too large (max 64KB)"
    try:
        return Path(path).read_text(errors="replace")
    except Exception as e:
        return f"ERROR: {e}"

def _mcp_tool_run_safe(command: str) -> str:
    if command.strip() not in _MCP_SAFE_CMDS:
        return "ERROR: command not in allowlist " + str(sorted(_MCP_SAFE_CMDS))
    try:
        r = subprocess.run(shlex.split(command), capture_output=True, text=True, timeout=5)
        return (r.stdout + r.stderr)[:4096] or "(no output)"
    except Exception as e:
        return f"ERROR: {e}"

_MCP_TOOLS = [
    {"name": "system_health", "description": "桌面系统组件健康状态（VNC/XFCE/websockify/sshd/网关）与负载",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "snapshot_latest", "description": "最新系统快照的 sha256、大小、时间与最近提交",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "list_dir", "description": "列出白名单目录内容（/workspace/debian13-server 或 /backup/repo）",
     "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
    {"name": "read_file", "description": "读取白名单目录内的文本文件（最大 64KB）",
     "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
    {"name": "run_safe", "description": "执行白名单只读命令（uptime/df -h/free -h/date/hostname/ss -tln）",
     "inputSchema": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}},
]

def _mcp_call(name: str, args: dict):
    if name == "system_health": return _mcp_tool_system_health()
    if name == "snapshot_latest": return _mcp_tool_snapshot_latest()
    if name == "list_dir": return _mcp_tool_list_dir(str(args.get("path", "")))
    if name == "read_file": return _mcp_tool_read_file(str(args.get("path", "")))
    if name == "run_safe": return _mcp_tool_run_safe(str(args.get("command", "")))
    raise KeyError(name)

@app.post("/mcp")
async def mcp_endpoint(request: Request):
    """MCP Streamable HTTP 端点（Basic Auth 由中间件强制；工具集严格白名单）"""
    try:
        body = await request.json()
    except Exception:
        return JSONResponse(status_code=400, content={"jsonrpc": "2.0", "id": None,
                            "error": {"code": -32700, "message": "Parse error"}})
    method = body.get("method", "")
    rid = body.get("id")
    if method.startswith("notifications/"):
        return JSONResponse(status_code=202, content=None)
    def result(r):
        return {"jsonrpc": "2.0", "id": rid, "result": r}
    def error(code, msg):
        return {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": msg}}
    try:
        if method == "initialize":
            return result({"protocolVersion": _MCP_PROTOCOL_VERSION,
                           "capabilities": {"tools": {}},
                           "serverInfo": _MCP_SERVER_INFO})
        if method == "ping":
            return result({})
        if method == "tools/list":
            return result({"tools": _MCP_TOOLS})
        if method == "tools/call":
            params = body.get("params") or {}
            name = params.get("name", "")
            args = params.get("arguments") or {}
            try:
                text = _mcp_call(name, args)
            except KeyError:
                return error(-32602, f"unknown tool: {name}")
            return result({"content": [{"type": "text", "text": str(text)}]})
        return error(-32601, f"method not found: {method}")
    except Exception as e:
        return error(-32603, str(e)[:200])

@app.websocket("/websockify")
@app.websocket("/desktop/websockify")
async def ws_proxy(ws: WebSocket):
    await ws.accept()
    try:
        async with websockets.connect(
            "ws://127.0.0.1:6081/", max_size=None, ping_interval=None,
        ) as upstream:
            async def c2u():
                try:
                    async for msg in ws.iter_bytes():
                        await upstream.send(msg)
                except Exception:
                    pass
            async def u2c():
                try:
                    async for msg in upstream:
                        if isinstance(msg, str):
                            await ws.send_text(msg)
                        else:
                            await ws.send_bytes(msg)
                except Exception:
                    pass
            await asyncio.gather(c2u(), u2c())
    except WebSocketDisconnect:
        pass
    except Exception as e:
        try:
            await ws.close(code=1011, reason=str(e)[:120])
        except Exception:
            pass

# 注意：WebSocket 路由必须注册在 Mount("/desktop") 之前，
# 否则 Mount 会按路径前缀拦截 /desktop/websockify 并返回 403。
if NOVNC_DIR.exists():
    app.mount("/desktop", StaticFiles(directory=str(NOVNC_DIR), html=True), name="desktop")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "6080")),
                log_level="info", access_log=False)
