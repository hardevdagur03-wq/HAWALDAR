"""
Hawaldar launcher — starts both Nitro SSR (port 3001) and FastAPI (port 8000).
Press Ctrl+C to stop both.

Usage:
    python start.py
"""

import subprocess
import sys
import os
import time
import signal
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
FRONTEND_DIR = BASE_DIR / "autonomous-flow-suite-main"


def main():
    procs: list[subprocess.Popen] = []

    def shutdown(*_):
        print("\n[shutdown] stopping servers...")
        for p in procs:
            if p.poll() is None:
                p.terminate()
        for p in procs:
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    # 1) Nitro SSR dev server
    print(f"[hawaldar] starting Nitro SSR on port 3001 ...")
    api_key = os.getenv("HAWALDAR_API_KEY", "change_me_in_production")
    nitro = subprocess.Popen(
        ["npm", "run", "dev"],
        cwd=str(FRONTEND_DIR),
        env={
            **os.environ,
            "PORT": "3001",
            "VITE_API_KEY": api_key,
            "VITE_API_BASE_URL": "http://127.0.0.1:8000/api/v1",
        },
    )
    procs.append(nitro)

    # 2) FastAPI backend
    print(f"[hawaldar] starting FastAPI on port 8000 ...")
    api = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"],
        cwd=str(BASE_DIR),
        env={
            **os.environ,
            "HAWALDAR_API_KEY": api_key,
        },
    )
    procs.append(api)

    print("[hawaldar] both servers running. Ctrl+C to stop.")
    print(f"  Frontend : http://localhost:3001")
    print(f"  API      : http://localhost:8000")
    print(f"  Health   : http://localhost:8000/api/v1/health")

    # Wait for either process to exit
    while True:
        for p in procs:
            if p.poll() is not None:
                print(f"[hawaldar] process exited with code {p.returncode}")
                shutdown()
        time.sleep(1)


if __name__ == "__main__":
    main()
