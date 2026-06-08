"""
Hawaldar — Enterprise Social Media Automation Platform
FastAPI backend + Nitro SSR frontend proxy.

Run with:
    python start.py          # launches both FastAPI (8000) + Nitro (3001)
    python -m uvicorn main:app --reload   # FastAPI only (dev)
"""

import os
from pathlib import Path
from datetime import datetime, timezone

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

from api.router import api_router

load_dotenv(override=True)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent
FRONTEND_DIR = BASE_DIR / "autonomous-flow-suite-main"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
NITRO_PORT = int(os.getenv("NITRO_PORT", "8080"))
NITRO_URL = f"http://127.0.0.1:{NITRO_PORT}"

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
is_dev = os.getenv("HAWALDAR_ENV", "development").lower() == "development"

app = FastAPI(
    title="Hawaldar",
    description="Enterprise multi-account social media automation control plane",
    version="0.1.0",
    docs_url="/api/v1/docs" if is_dev else None,
    redoc_url="/api/v1/redoc" if is_dev else None,
    openapi_url="/api/v1/openapi.json" if is_dev else None,
)

# ---------------------------------------------------------------------------
# CORS — restrict to loopback and designated frontend ports
# ---------------------------------------------------------------------------
CORS_ORIGINS = [
    "http://localhost:3001",
    "http://localhost:8080",
    "http://localhost:8000",
    "http://127.0.0.1:3001",
    "http://127.0.0.1:8080",
    "http://127.0.0.1:8000",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Rate Limiting Middleware
# ---------------------------------------------------------------------------
import time

RATE_LIMIT_WINDOWS = {
    "/api/v1/accounts": (10, 60),      # 10 requests per 60s per IP
    "/api/v1/proxies": (20, 60),       # 20 requests per 60s per IP
    "/api/v1/dead-letters": (30, 60),  # 30 requests per 60s per IP
}
DEFAULT_LIMIT = (100, 60)              # Default: 100 requests per 60s per IP
_request_history = {}


@app.middleware("http")
async def rate_limiter_middleware(request: Request, call_next):
    path = request.url.path
    if not path.startswith("/api/v1"):
        return await call_next(request)

    client_ip = request.client.host if request.client else "127.0.0.1"

    limit, window = DEFAULT_LIMIT
    route_key = None
    for route, (l, w) in RATE_LIMIT_WINDOWS.items():
        if path.startswith(route):
            limit, window = l, w
            route_key = route
            break

    if not route_key:
        route_key = "default"

    now = time.time()
    history_key = (client_ip, route_key)

    history = [t for t in _request_history.get(history_key, []) if now - t < window]
    if len(history) >= limit:
        return JSONResponse(
            status_code=429,
            content={"detail": "Rate limit exceeded. Please try again later."}
        )

    history.append(now)
    _request_history[history_key] = history

    return await call_next(request)


# ---------------------------------------------------------------------------
# Include modular API router (all /api/v1/* endpoints)
# ---------------------------------------------------------------------------
app.include_router(api_router)


# ---------------------------------------------------------------------------
# Standalone health endpoint
# ---------------------------------------------------------------------------
@app.get("/api/v1/health", tags=["system"])
async def health_check():
    """Verify backend + frontend SSR server status."""
    nitro_ok = False
    try:
        async with httpx.AsyncClient(timeout=2.0) as c:
            r = await c.get(f"{NITRO_URL}/", follow_redirects=True)
            nitro_ok = r.status_code < 500
    except Exception:
        pass

    return {
        "status": "ok",
        "service": "hawaldar",
        "version": app.version,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "frontend": "up" if nitro_ok else "down",
    }


# ---------------------------------------------------------------------------
# Favicon — prevent 404 before proxy catch-all
# ---------------------------------------------------------------------------
@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    return Response(content=b"", media_type="image/x-icon", status_code=204)

@app.get("/favicon.png", include_in_schema=False)
async def favicon_png():
    return Response(content=b"", media_type="image/png", status_code=204)

# ---------------------------------------------------------------------------
# Frontend proxy → Nitro SSR  (MUST be last route)
# ---------------------------------------------------------------------------
@app.api_route(
    "/{full_path:path}",
    methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
    include_in_schema=False,
)
async def proxy_frontend(request: Request, full_path: str):
    target = f"{NITRO_URL}/{full_path}"
    if request.url.query:
        target += f"?{request.url.query}"

    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.request(
                method=request.method,
                url=target,
                headers={k: v for k, v in request.headers.items() if k.lower() != "host"},
                content=await request.body(),
            )
        except httpx.ConnectError:
            return JSONResponse(
                {
                    "error": "Frontend SSR not reachable",
                    "hint": f"Start Nitro: cd {FRONTEND_DIR.name} && npm run dev",
                },
                status_code=502,
            )

    skip = {"content-encoding", "content-length", "transfer-encoding"}
    headers = {k: v for k, v in resp.headers.items() if k.lower() not in skip}
    return Response(content=resp.content, status_code=resp.status_code, headers=headers)
