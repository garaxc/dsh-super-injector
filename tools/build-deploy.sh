#!/bin/bash
# 构建并部署修复后的注入器（copy-based link_pkg）
set -uo pipefail
export PATH="/d/app/Modex-MH-Agent/runtime/node:$PATH"

SRC="/f/dsh-plugin/dsh-super-injector"
CK="/c/Users/Administrator/.dsh/super-injector/checkout"
LIVE="/d/dsh/super-injector"

echo "=== 1) 编译 host（tsc，用隔离 checkout）==="
cd "$SRC" || exit 1
TSC="$CK/node_modules/.bin/tsc.cmd"
[ -x "$TSC" ] || TSC="$CK/node_modules/.bin/tsc"
echo "tsc = $TSC"

# 构建期依赖：copy 到项目内 node_modules（不碰源）
node -e "
const fs=require('fs'),path=require('path');
const CK=process.argv[1], SRC=process.argv[2];
const pairs=[['@deepseek-ai/cordis','vendor/cordis'],['cosmokit','vendor/cosmokit'],['@deepseek-ai/schemastery','vendor/schemastery'],['@deepseek-ai/dsh-tools','packages/core/tools'],['@deepseek-ai/dsh-llm','packages/llm/llm'],['@deepseek-ai/dsh-system-prompt','packages/core/system-prompt'],['@types/node','node_modules/@types/node']];
for(const [name,rel] of pairs){
  const src=path.join(CK,rel), dst=path.join(SRC,'node_modules',...name.split('/'));
  if(!fs.existsSync(src)){ console.log('  MISS src '+src); continue }
  try{ const st=fs.lstatSync(dst); if(st.isSymbolicLink()) fs.rmdirSync(dst); else fs.rmSync(dst,{recursive:true,force:true}) }catch{}
  fs.mkdirSync(path.dirname(dst),{recursive:true});
  fs.cpSync(src,dst,{recursive:true,dereference:false,filter:(s)=>path.basename(s)!=='node_modules'});
  console.log('  ✓ '+name);
}
" "$CK" "$SRC" 2>&1

echo
echo "=== 2) tsc 编译 ==="
"$TSC" -p tsconfig.json 2>&1 | tail -25
echo "tsc exit=${PIPESTATUS[0]}"

if [ ! -f "$SRC/lib/index.js" ]; then echo "✗ lib/index.js 未生成"; exit 1; fi
echo "lib/index.js 大小: $(stat -c%s "$SRC/lib/index.js") 字节"
node --check "$SRC/lib/index.js" && echo "node --check OK"

echo
echo "=== 3) 部署到活跃路径 $LIVE/lib ==="
mkdir -p "$LIVE/lib"
cp "$SRC/lib/index.js" "$LIVE/lib/index.js"
echo "已部署: $(stat -c%s "$LIVE/lib/index.js") 字节"

echo
echo "=== 4) 验证部署后的修复生效 ==="
for pat in 'cpSync(src,dst' 'use_pkg()' 'stripLinks'; do
  n=$(grep -c "$pat" "$LIVE/lib/index.js" 2>/dev/null || echo 0)
  printf '  %-22s 出现 %s 次\n' "$pat" "$n"
done
echo "--- 旧危险模式（应为 0 或仅在兜底分支）---"
printf '  symlinkSync(target, link: %s 次\n' "$(grep -c 'symlinkSync(target, link' "$LIVE/lib/index.js" 2>/dev/null || echo 0)"

echo
echo "=== 5) 加载冒烟 ==="
node -e "import('file:///D:/dsh/super-injector/lib/index.js').then(m=>console.log('  LOAD OK:',Object.keys(m).join(',')),e=>console.log('  LOAD FAIL:',String(e).slice(0,200)))" 2>&1
