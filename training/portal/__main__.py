"""python -m portal [--port 8765]"""

import argparse

from .app import create_app
from .train_job import JOBS_DIR

ap = argparse.ArgumentParser(description="HarvestShelf training portal (local only)")
ap.add_argument("--port", type=int, default=8765)
a = ap.parse_args()
JOBS_DIR.mkdir(parents=True, exist_ok=True)
print(f"Training portal: http://127.0.0.1:{a.port}")
create_app().run(host="127.0.0.1", port=a.port, threaded=True)
