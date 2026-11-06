#!/usr/bin/env python3
"""Secure Desktop Gateway — FastAPI + noVNC + websockify WebSocket proxy.

Every entry point except /healthz and /favicon.ico requires HTTP Basic Auth.
Credentials come from the environment (GATEWAY_USER / GATEWAY_PASS), filled by
the secrets intake (SECRETS.md). There are NO hardcoded defaults: this
repository is public and must stay secret-free.

The password is compared as standard UTF-8 bytes, so Arabic (and any UTF-8)
passwords validate correctly.
"""
import os
import sys
import base64
import asyncio
import secrets
from pathlib import Path

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
import websockets

APP_DIR = Path("/opt/desktop-gw")
NOVNC_DIR = APP_DIR / "novnc"
APP_DIR.mkdir(parents=True, exist_ok=True)

# --- Authentication config (values from env only — secrets intake) -----------
_AUTH_USER = os.environ.get("GATEWAY_USER", "")
_AUTH_PASS = os.environ.get("GATEWAY_PASS", "")
_AUTH_REALM = "Debian 13 Cloud Desktop - Protected Area"

if not _AUTH_USER or not _AUTH_PASS:
    print(
        "FATAL: GATEWAY_USER/GATEWAY_PASS are not set.\n"
        "Ask the user for the gateway credentials (see SECRETS.md), write them "
        "to .env, and restart. NEVER hardcode credentials here.",
        file=sys.stderr,
    )
    sys.exit(1)

# Build expected Basic Auth header in UTF-8
_RAW_PAIR = f"{_AUTH_USER}:{_AUTH_PASS}".encode("utf-8")
_VALID_AUTH = "Basic " + base64.b64encode(_RAW_PAIR).decode("ascii")

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def _unauth():
    return JSONResponse(
        status_code=401,
        content={"detail": "Authentication required"},
        headers={
            "WWW-Authenticate": f'Basic realm="{_AUTH_REALM}", charset="UTF-8"'
        },
    )


def _check(req: Request) -> bool:
    auth = req.headers.get("Authorization", "")
    if not auth:
        return False
    # Standard digest comparison
    if secrets.compare_digest(auth.strip(), _VALID_AUTH):
        return True
    # Tolerate proxies that join multiple headers with commas
    if "," in auth:
        return any(
            secrets.compare_digest(p.strip(), _VALID_AUTH) for p in auth.split(",")
        )
    return False


@app.middleware("http")
async def auth_gate(request: Request, call_next):
    # Open routes: the watchdog needs an unauthenticated liveness probe.
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
    return RedirectResponse(
        url="/desktop/vnc.html?autoconnect=1&resize=scale&path=websockify",
        status_code=302,
    )


if NOVNC_DIR.exists():
    app.mount(
        "/desktop", StaticFiles(directory=str(NOVNC_DIR), html=True), name="desktop"
    )


@app.websocket("/websockify")
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


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "6080")),
        log_level="info",
        access_log=False,
    )
