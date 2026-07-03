#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[guard] Existing labs before deploy:"
sudo containerlab inspect --all || true

echo "[deploy] Deploy only interop-shownet"
sudo containerlab deploy -t interop-shownet.clab.yml

echo "[fix] Start iouyap only for interop-shownet Cisco IOL nodes"
sudo ./tools/start_iouyap.sh

echo "[done] Current labs:"
sudo containerlab inspect --all
