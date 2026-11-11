#!/usr/bin/env bash
# arch-diagram-autocommit.md S1：架構圖隨 commit 產生（bin/arch-diagram-precommit）的測試。
#
# 用法：HOOKSET=new|old script/arch_diagram_precommit_test.sh
#   new：受測的新做法——pre-commit 在 detect-changes 之後呼叫 bin/arch-diagram-precommit，pre-push 不再產生
#   old：改版前的做法——pre-commit 只有 detect-changes；pre-push 產生架構圖但不 commit、永遠放行
#
# 每案在 mktemp -d 建工作 repo＋bare 遠端。真產生器會把目錄名稱寫進圖的標題（S0 r1 質詢 2），
# 所以用替身：
#   - PATH 最前面放假的 code-review-graph：`update` 依工作區 app/*.rb 的 class 名稱重寫
#     .code-review-graph/graph.db（模擬真的增量更新）；`detect-changes` 什麼都不做
#   - 產生指令經 ARCH_DIAGRAM_GENERATE_CMD 換成替身：把 graph.db 內容寫進 docs/ 三個圖檔
# 正式環境沒有設定 ARCH_DIAGRAM_GENERATE_CMD，走真的兩支產生器；update 一律走 PATH 上的 code-review-graph。
set -u

HOOKSET="${HOOKSET:-new}"
SRC_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -r -f -- "$WORK"' EXIT

# ── 替身 ────────────────────────────────────────────────────────────────────
mkdir -p "$WORK/shim"
cat >"$WORK/shim/code-review-graph" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  update)
    root=$(git rev-parse --show-toplevel) || exit 1
    mkdir -p "$root/.code-review-graph"
    { grep -ho '^class [A-Za-z0-9_]*' "$root"/app/*.rb 2>/dev/null | sort; } >"$root/.code-review-graph/graph.db"
    echo "Incremental: shim update" ;;
  status)
    root=$(git rev-parse --show-toplevel) || exit 1
    echo "Nodes: $(grep -c . "$root/.code-review-graph/graph.db" 2>/dev/null || echo 0)" ;;
  *) exit 0 ;;
esac
EOF
cat >"$WORK/shim/stub-gen" <<'EOF'
#!/usr/bin/env bash
root=$(git rev-parse --show-toplevel) || exit 1
[ -f "$root/.code-review-graph/graph.db" ] || { echo "stub-gen: 找不到 graph.db" >&2; exit 1; }
mkdir -p "$root/docs"
for f in architecture_spec.yml fairprice-architecture.svg fairprice-architecture.html; do
  { echo "# $f"; cat "$root/.code-review-graph/graph.db"; } >"$root/docs/$f"
done
EOF
chmod +x "$WORK/shim/code-review-graph" "$WORK/shim/stub-gen"
export PATH="$WORK/shim:$PATH"
export ARCH_DIAGRAM_GENERATE_CMD="stub-gen"

# ── hook 內容 ──────────────────────────────────────────────────────────────
# 既有 pre-commit（code-review-graph install 產生的原文）
PRE_COMMIT_BASE='#!/bin/sh
# Installed by code-review-graph. Remove this file to disable pre-commit graph checks.
if command -v code-review-graph >/dev/null 2>&1; then
    code-review-graph detect-changes --brief || true
fi'
# 舊 pre-push：產生圖、不 commit、永遠 exit 0（產生器換成替身，結構同 .git/hooks/pre-push 舊版）
PRE_PUSH_OLD='#!/bin/bash
cat > /dev/null
stub-gen >&2 || echo "架構圖渲染失敗（不影響推送）" >&2
exit 0'

setup_repo() { # $1=名稱 → 建立工作 repo（含初始 commit 與已 push 的遠端），印出路徑
  local r="$WORK/$1" remote="$WORK/$1.git"
  git init -q --bare "$remote"
  git init -q "$r"
  git -C "$r" config user.email test@example.com
  git -C "$r" config user.name test
  mkdir -p "$r/app" "$r/bin"
  printf '.code-review-graph/\n' >"$r/.gitignore"
  printf 'class Alpha\nend\n' >"$r/app/alpha.rb"
  printf '# readme\n' >"$r/README.md"
  (cd "$r" && code-review-graph update >/dev/null && stub-gen)
  if [ "$HOOKSET" = "new" ]; then
    cp "$SRC_REPO/bin/arch-diagram-precommit" "$r/bin/arch-diagram-precommit" 2>/dev/null
  fi
  git -C "$r" add -A && git -C "$r" commit -q -m init
  git -C "$r" remote add origin "$remote"
  git -C "$r" push -q origin HEAD:main 2>/dev/null
  if [ "$HOOKSET" = "new" ]; then
    printf '%s\nbin/arch-diagram-precommit || exit 1\n' "$PRE_COMMIT_BASE" >"$r/.git/hooks/pre-commit"
  else
    printf '%s\n' "$PRE_COMMIT_BASE" >"$r/.git/hooks/pre-commit"
    printf '%s\n' "$PRE_PUSH_OLD" >"$r/.git/hooks/pre-push"
    chmod +x "$r/.git/hooks/pre-push"
  fi
  chmod +x "$r/.git/hooks/pre-commit"
  echo "$r"
}

check() { # $1=案例 $2=0/1 $3=說明
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); echo "PASS $1：$3"
  else FAIL=$((FAIL + 1)); echo "FAIL $1：$3"; fi
}

committed_docs() { # $1=repo → 最新 commit 內含的圖檔數
  git -C "$1" show --name-only --format= HEAD | grep -c '^docs/'
}

# ── T1 程式改動使圖需更新 → commit 含新圖，push 後遠端含新圖 ──────────────
r=$(setup_repo t1)
printf 'class Beta\nend\n' >"$r/app/beta.rb"
git -C "$r" add app/beta.rb
(cd "$r" && git commit -q -m "add Beta" 2>"$WORK/t1.err")
n=$(committed_docs "$r")
(cd "$r" && git push -q origin HEAD:main 2>/dev/null)
remote_spec=$(git -C "$WORK/t1.git" show main:docs/architecture_spec.yml 2>/dev/null)
if [ "$n" -eq 3 ] && echo "$remote_spec" | grep -q 'class Beta'; then rc=0; else rc=1; fi
check T1 "$rc" "commit 內圖檔數=$n；遠端 spec 含 Beta=$(echo "$remote_spec" | grep -c 'class Beta')；push 後工作區 docs 變動=$(git -C "$r" status --porcelain -- docs | wc -l)"

# ── T2 圖無需更新 → commit 不含圖檔，push 一次成功、不多 commit ──────────────
r=$(setup_repo t2)
printf '# readme v2\n' >"$r/README.md"
git -C "$r" add README.md
before=$(git -C "$r" rev-list --count HEAD)
(cd "$r" && git commit -q -m "readme" 2>"$WORK/t2.err")
n=$(committed_docs "$r")
(cd "$r" && git push -q origin HEAD:main 2>/dev/null); push_rc=$?
after=$(git -C "$r" rev-list --count HEAD)
if [ "$n" -eq 0 ] && [ "$push_rc" -eq 0 ] && [ $((after - before)) -eq 1 ] && [ -z "$(git -C "$r" status --porcelain)" ]; then rc=0; else rc=1; fi
check T2 "$rc" "commit 內圖檔數=$n；push 結束碼=$push_rc；新增 commit 數=$((after - before))；工作區變動=$(git -C "$r" status --porcelain | wc -l)"

# ── T3 產生指令失敗 → commit 中止並印出錯誤 ───────────────────────────────
r=$(setup_repo t3)
printf 'class Gamma\nend\n' >"$r/app/gamma.rb"
git -C "$r" add app/gamma.rb
head_before=$(git -C "$r" rev-parse HEAD)
(cd "$r" && ARCH_DIAGRAM_GENERATE_CMD=false git commit -q -m "add Gamma" 2>"$WORK/t3.err"); commit_rc=$?
head_after=$(git -C "$r" rev-parse HEAD)
if [ "$commit_rc" -ne 0 ] && [ "$head_before" = "$head_after" ] && grep -q "架構圖產生失敗" "$WORK/t3.err"; then rc=0; else rc=1; fi
check T3 "$rc" "commit 結束碼=$commit_rc；HEAD 不變=$([ "$head_before" = "$head_after" ] && echo 是 || echo 否)；stderr 含「架構圖產生失敗」=$(grep -c "架構圖產生失敗" "$WORK/t3.err")"

# ── T4 工作區另有無關未 commit 檔 → 自動加入的只有圖檔 ─────────────────────
r=$(setup_repo t4)
printf 'class Delta\nend\n' >"$r/app/delta.rb"
printf '# readme dirty\n' >"$r/README.md"   # 已追蹤、未暫存
printf 'scratch\n' >"$r/notes.txt"          # 未追蹤
git -C "$r" add app/delta.rb
(cd "$r" && git commit -q -m "add Delta" 2>"$WORK/t4.err")
files=$(git -C "$r" show --name-only --format= HEAD | sort | tr '\n' ' ')
if ! git -C "$r" show --name-only --format= HEAD | grep -qE '^(README.md|notes.txt)$' &&
   [ "$(committed_docs "$r")" -eq 3 ] && git -C "$r" status --porcelain | grep -q '^ M README.md' &&
   git -C "$r" status --porcelain | grep -q '^?? notes.txt'; then rc=0; else rc=1; fi
check T4 "$rc" "commit 內檔案=[$files]；README.md／notes.txt 仍留在工作區=$(git -C "$r" status --porcelain | grep -cE 'README.md|notes.txt')"

# ── T5 不經 Claude Code 直接改程式後 commit → graph.db 先被更新，圖反映修改 ──
r=$(setup_repo t5)
printf 'class Epsilon\nend\n' >"$r/app/epsilon.rb"   # 只改檔，沒有任何 Claude 工具呼叫，graph.db 未更新
stale=$(grep -c Epsilon "$r/.code-review-graph/graph.db")
git -C "$r" add app/epsilon.rb
(cd "$r" && git commit -q -m "add Epsilon" 2>"$WORK/t5.err")
fresh=$(grep -c Epsilon "$r/.code-review-graph/graph.db")
in_commit=$(git -C "$r" show HEAD:docs/architecture_spec.yml 2>/dev/null | grep -c Epsilon)
if [ "$stale" -eq 0 ] && [ "$fresh" -eq 1 ] && [ "$in_commit" -eq 1 ]; then rc=0; else rc=1; fi
check T5 "$rc" "commit 前 graph.db 含 Epsilon=$stale；commit 後=$fresh；commit 內 spec 含 Epsilon=$in_commit"

# ── T6 bin/arch-diagram-precommit 不存在或不可執行 → commit 中止並印出錯誤 ──
for variant in 不存在 不可執行; do
  r=$(setup_repo "t6-$variant")
  if [ "$variant" = "不存在" ]; then
    git -C "$r" rm -q --cached bin/arch-diagram-precommit 2>/dev/null; rm -f "$r/bin/arch-diagram-precommit"
  else
    chmod -x "$r/bin/arch-diagram-precommit" 2>/dev/null
  fi
  printf 'class Zeta\nend\n' >"$r/app/zeta.rb"
  git -C "$r" add app/zeta.rb
  head_before=$(git -C "$r" rev-parse HEAD)
  (cd "$r" && git commit -q -m "add Zeta" 2>"$WORK/t6.err"); commit_rc=$?
  head_after=$(git -C "$r" rev-parse HEAD)
  if [ "$commit_rc" -ne 0 ] && [ "$head_before" = "$head_after" ] && grep -q "arch-diagram-precommit" "$WORK/t6.err"; then rc=0; else rc=1; fi
  check "T6（$variant）" "$rc" "commit 結束碼=$commit_rc；HEAD 不變=$([ "$head_before" = "$head_after" ] && echo 是 || echo 否)；stderr：$(tr '\n' ' ' <"$WORK/t6.err" | cut -c1-120)"
done

# ── T7 剛 clone、沒有 graph.db／graph.db 是空的 → commit 中止並提示先 build ──
# 2026-11-11 實測：真的 code-review-graph update 在沒有 graph.db 時會建出 0 節點的空 graph.db 並 exit 0，
# 產生器接著產出只剩 1 層的圖，被當成「架構圖已更新」併進 commit。必須在 update 前擋下。
for variant in 無graph.db 空graph.db; do
  r=$(setup_repo "t7-$variant")
  if [ "$variant" = "無graph.db" ]; then rm -r -f -- "$r/.code-review-graph"
  else : >"$r/.code-review-graph/graph.db"; fi
  printf 'class Eta\nend\n' >"$r/app/eta.rb"
  git -C "$r" add app/eta.rb
  head_before=$(git -C "$r" rev-parse HEAD)
  (cd "$r" && git commit -q -m "add Eta" 2>"$WORK/t7.err"); commit_rc=$?
  head_after=$(git -C "$r" rev-parse HEAD)
  if [ "$commit_rc" -ne 0 ] && [ "$head_before" = "$head_after" ] && grep -q "code-review-graph build" "$WORK/t7.err"; then rc=0; else rc=1; fi
  check "T7（$variant）" "$rc" "commit 結束碼=$commit_rc；HEAD 不變=$([ "$head_before" = "$head_after" ] && echo 是 || echo 否)；stderr 含「code-review-graph build」=$(grep -c "code-review-graph build" "$WORK/t7.err")"
done

echo "HOOKSET=$HOOKSET → $PASS 通過，$FAIL 失敗"
[ "$FAIL" -eq 0 ]
