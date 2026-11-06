#!/usr/bin/env python3
"""
Debian 13 Cloud Desktop — 一键 SSH 客户端（零依赖，只需 python3 + 系统自带 ssh）

原理：平台公网入口只支持 HTTP/WebSocket，因此 SSH 通过已认证的 WebSocket 隧道承载：
    本地 ssh  -> 127.0.0.1:2222 -> WSS 隧道 (Basic Auth) -> 网关 -> chroot sshd:22

用法：
    python3 ssh-connect.py                 # 直接登录
    python3 ssh-connect.py "blender -v"    # 登录并执行一条命令后退出
    SSH_USER=debian SSH_PORT=2222 python3 ssh-connect.py

本脚本会自动：
    1) 用 Basic Auth 从固定公网地址下载 SSH 私钥（首次）
    2) 在本地 2222 端口起 WebSocket<->TCP 桥
    3) 调用系统 ssh 完成登录
"""
import asyncio, base64, os, subprocess, sys, tempfile, shutil, pathlib

HOST = "f2c8433550f81c49.sg.agentos-app.run"
BASE = f"https://{HOST}"
WS_URL = f"wss://{HOST}/ssh"
USER = os.environ.get("SSH_USER", "debian")
USERNAME = os.environ.get("GATEWAY_USER", "admin")
PASSWORD = os.environ.get("GATEWAY_PASS", "سيرفر_سحابي_آمن@13")
LOCAL_PORT = int(os.environ.get("SSH_PORT", "2222"))
AUTH = base64.b64encode(f"{USERNAME}:{PASSWORD}".encode("utf-8")).decode()

def ensure_key() -> str:
    key_dir = pathlib.Path(os.environ.get("SSH_KEY_DIR", "~/.debian13-desktop")).expanduser()
    key_dir.mkdir(parents=True, exist_ok=True)
    key_path = key_dir / "id_ed25519"
    if not key_path.exists():
        print(f"[*] 下载 SSH 私钥 -> {key_path}")
        subprocess.run(["curl", "-sfL", "-u", f"{USERNAME}:{PASSWORD}",
                        "-o", str(key_path), f"{BASE}/ssh/id_ed25519"], check=True)
        os.chmod(key_path, 0o600)
    return str(key_path)

def start_bridge() -> subprocess.Popen:
    """启动本地 TCP<->WSS 桥（复用本文件作为 bridge 子进程）"""
    return subprocess.Popen([sys.executable, os.path.abspath(__file__), "--bridge-only"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

async def bridge():
    try:
        import websockets
    except ImportError:
        print("错误：本客户端需要 websockets 库，请先执行： pip install websockets")
        sys.exit(1)

    async def handle(reader, writer):
        try:
            async with websockets.connect(
                WS_URL,
                additional_headers={"Authorization": f"Basic {AUTH}"},
                max_size=None, open_timeout=20,
            ) as ws:
                async def tcp_to_ws():
                    try:
                        while True:
                            data = await reader.read(65536)
                            if not data:
                                break
                            await ws.send(data)
                    except Exception:
                        pass
                    finally:
                        try: await ws.close()
                        except Exception: pass
                async def ws_to_tcp():
                    try:
                        async for msg in ws:
                            writer.write(msg if isinstance(msg, bytes) else msg.encode())
                            await writer.drain()
                    except Exception:
                        pass
                    finally:
                        try: writer.close()
                        except Exception: pass
                await asyncio.gather(tcp_to_ws(), ws_to_tcp())
        except Exception as e:
            print(f"桥接失败: {e}", file=sys.stderr)

    server = await asyncio.start_server(handle, "127.0.0.1", LOCAL_PORT)
    async with server:
        await server.serve_forever()

def wait_port(port: int, timeout: int = 15) -> bool:
    import socket, time
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket() as s:
            s.settimeout(1)
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return True
        time.sleep(0.3)
    return False

def main():
    if "--bridge-only" in sys.argv:
        asyncio.run(bridge())
        return

    key = ensure_key()
    proc = start_bridge()
    try:
        if not wait_port(LOCAL_PORT):
            print("错误：本地隧道端口未就绪"); sys.exit(1)
        cmd = ["ssh", "-o", "StrictHostKeyChecking=no",
               "-o", "UserKnownHostsFile=/dev/null",
               "-o", "ConnectTimeout=20",
               "-i", key, "-p", str(LOCAL_PORT), f"{USER}@127.0.0.1"]
        extra = [a for a in sys.argv[1:] if not a.startswith("-")]
        if extra:
            cmd += ["--"] + extra
        sys.exit(subprocess.call(cmd))
    finally:
        proc.terminate()

if __name__ == "__main__":
    main()
