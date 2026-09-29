#!/usr/bin/env bash
# docs/*.drawio.svg を GitHub 表示向けに書き出し直す（図データは SVG に埋め込まれていて、これが原本）
# - ライトテーマ固定（ダークテーマで線や文字が背景に溶けないように）
# - 背景を白で固定
# - foreignObject 用の PNG フォールバックを除去（ファイルサイズ削減、ブラウザ表示には不要）
# draw.io で .drawio.svg を編集・保存すると上記が既定値に戻るので、保存後に make diagram を実行してからコミットする
set -euo pipefail

drawio_bin="${DRAWIO:-drawio}"
command -v "$drawio_bin" >/dev/null || { echo "draw.io CLI が見つからない（brew install --cask drawio）" >&2; exit 1; }

for src in docs/*.drawio.svg; do
  dst="$src"
  tmp="$(mktemp -t diagram).svg"
  "$drawio_bin" -x -f svg -e -b 10 --theme light -o "$tmp" "$src" >/dev/null 2>&1
  python3 - "$tmp" "$dst" <<'PY'
import re, sys, xml.dom.minidom
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()
s = re.sub(r'<image [^>]*xlink:href="data:image/png;base64,[^"]*"[^>]*/>', "", s)
s = re.sub(r'(<svg [^>]*style=")([^"]*)"',
           lambda m: m.group(1) + re.sub(r"background(-color)?:\s*[^;]*;?\s*", "", m.group(2)).strip() + ' background-color: #ffffff;"',
           s, count=1)
xml.dom.minidom.parseString(s.encode())
open(dst, "w", encoding="utf-8").write(s)
print(f"{dst}: {len(s.encode())} bytes")
PY
  rm -f "$tmp"
done
