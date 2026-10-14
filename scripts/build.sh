#!/bin/bash
# Build dsh-super-injector: compile src/ → lib/ with the dsh checkout's tsc.
# Requires DSH_CHECKOUT pointing at a dsh source checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CHECKOUT="${DSH_CHECKOUT:-}"
if [ -z "$CHECKOUT" ] || [ ! -d "$CHECKOUT/packages" ]; then
  echo "build: cannot locate the dsh checkout (set DSH_CHECKOUT)" >&2
  exit 1
fi

TSC="$CHECKOUT/node_modules/.bin/tsc"
if [ ! -x "$TSC" ]; then
  echo "build: tsc not found at $TSC" >&2
  exit 1
fi

link_pkg() {
  local target="$CHECKOUT/$2"
  if [ ! -e "$target" ]; then
    echo "build: dependency target missing: $target" >&2
    exit 1
  fi
  node -e "
    const fs = require('fs');
    const path = require('path');
    const link = path.resolve(process.argv[1]);
    const target = path.resolve(process.argv[2]);
    fs.rmSync(link, { recursive: true, force: true });
    fs.mkdirSync(path.dirname(link), { recursive: true });
    fs.symlinkSync(target, link, process.platform === 'win32' ? 'junction' : 'dir');
  " "node_modules/$1" "$target"
}

echo "=== Linking build dependencies (checkout: $CHECKOUT) ==="
mkdir -p node_modules/@deepseek-ai
node -e "const fs=require('fs');fs.rmSync('node_modules/@standard-schema',{recursive:true,force:true})"
# ⚠️ 链接名必须与 src 的 import 说明符**逐字一致**（实测踩坑 2026-10-15）：
# 提交 1df6cde 把源码 import 从裸名（cordis/schemastery）改成 scoped
# （@deepseek-ai/cordis 等），但本文件仍链裸名 —— tsc 直接报 6 个
# TS2307「Cannot find module '@deepseek-ai/cordis'」，lib 根本编不出来。
# 决定性证据：补上 scoped 链接后 6 个 TS2307 全部消失、lib/index.js 正常产出。
link_pkg @deepseek-ai/cordis vendor/cordis
link_pkg @deepseek-ai/cosmokit vendor/cosmokit
link_pkg @deepseek-ai/schemastery vendor/schemastery
link_pkg @deepseek-ai/dsh-tools packages/core/tools
# src 直接 import 了 @deepseek-ai/dsh-llm（LLM 自主 loop 用）——缺它同样 TS2307。
link_pkg @deepseek-ai/dsh-llm packages/llm/llm
link_pkg @deepseek-ai/dsh-system-prompt packages/core/system-prompt
link_pkg @deepseek-ai/cordis-plugin-loader vendor/loader

# @types/node：tsconfig 写了 types:["node"]，缺它就 TS2688 直接编不动（实测踩坑：
# 没有 node_modules 的干净检出/换机器即构建失败——产线必须自洽，不靠某台机器的残留）。
TYPES_NODE="$CHECKOUT/node_modules/@types/node"
if [ ! -d "$TYPES_NODE" ]; then
  echo "build: @types/node not found at $TYPES_NODE" >&2
  exit 1
fi
node -e "
  const fs = require('fs');
  const path = require('path');
  const link = path.resolve('node_modules/@types/node');
  const target = path.resolve(process.argv[1]);
  fs.rmSync(link, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(target, link, process.platform === 'win32' ? 'junction' : 'dir');
" "$TYPES_NODE"

STD_SCHEMA=$(find "$CHECKOUT/node_modules/.pnpm" -maxdepth 1 -type d -iname '@standard-schema+spec@*' 2>/dev/null | head -1)
if [ -n "$STD_SCHEMA" ]; then
  node -e "
    const fs = require('fs');
    const path = require('path');
    fs.rmSync('node_modules/@standard-schema', { recursive: true, force: true });
    fs.mkdirSync('node_modules/@standard-schema', { recursive: true });
    fs.symlinkSync(path.resolve(process.argv[1]), path.resolve('node_modules/@standard-schema/spec'), process.platform === 'win32' ? 'junction' : 'dir');
  " "$STD_SCHEMA/node_modules/@standard-schema/spec"
else
  echo "build: @standard-schema/spec not found; skipLibCheck should cover it" >&2
fi

echo "=== Compiling src → lib (tsc $("$TSC" --version)) ==="
"$TSC" -p tsconfig.json

echo "=== Build complete ==="
ls -la lib/ lib/types/ 2>/dev/null
