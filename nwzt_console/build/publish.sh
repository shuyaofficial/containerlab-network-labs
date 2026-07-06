#!/usr/bin/env bash
# nwzt_console/src → docs/console/ へ公開コピー（GitHub Pages が配信）
# build.mjs(MD→HTML) は docs/ を丸ごと消さないため、MDビルドの後でも前でも可。
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"          # nwzt_console
ROOT="$(cd "$HERE/.." && pwd)"                      # Mac仮想環境構築
DEST="$ROOT/docs/console"
mkdir -p "$DEST"
cp -f "$HERE/src/"*.html "$HERE/src/"*.css "$HERE/src/"*.js "$DEST/"
echo "published → $DEST"
ls -1 "$DEST"
