#!/usr/bin/env bash
# World-Rollback State-Machine Fuzzer runner (SBCL 2.6.10 + CCL 1.14)
set -euo pipefail
cd "$(dirname "$0")"

COUNT="${1:-200}"
WORKERS="${2:-6}"

python3 gen_world_rollback.py \
  --mode both \
  --seed-start 1000 \
  --count "$COUNT" \
  --workers "$WORKERS" \
  --out-dir fuzz_campaign_clean
