"""
Hawaldar — Global configuration.
"""

from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

# --- Database ---
DB_PATH = BASE_DIR / "data" / "hawaldar.db"

# --- Worker Pool ---
MAX_CONCURRENT_WORKERS = 5
TASK_CLAIM_TIMEOUT_SEC = 600

# --- Anti-detect Browser ---
ADSPOWER_API = "http://127.0.0.1:50325"

# --- Platforms ---
PLATFORM_CAPS = {
    "twitter": {"daily_posts": 50, "daily_scrapes": 10},
    "facebook": {"daily_posts": 25, "daily_scrapes": 10},
    "instagram": {"daily_posts": 25, "daily_scrapes": 10},
}
