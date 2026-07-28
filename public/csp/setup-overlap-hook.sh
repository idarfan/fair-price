#!/bin/bash
# 執行此腳本以安裝 CSP HTML 交疊檢查 hook
# 用法：bash /home/idarfan/csp/setup-overlap-hook.sh

set -e

HOOK_PATH="/home/idarfan/.claude/hooks/post-bash-csp-html-overlap-check.sh"
SETTINGS_PATH="/home/idarfan/.claude/settings.json"

# ── 1. 建立 hook 腳本 ──────────────────────────────────────
cat > "$HOOK_PATH" << 'HOOK_CONTENT'
#!/bin/bash
# PostToolUse(Bash): CSP HTML 修改後強制 Playwright 交疊檢查
INPUT=$(cat)
CMD=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except:
    print('')
" 2>/dev/null)

[ -z "$CMD" ] && exit 0
echo "$CMD" | grep -q 'python3' || exit 0
echo "$CMD" | grep -qiE '/home/idarfan/csp/.*\.html|option-basics-lesson|csp-comic|cc-covered' || exit 0

HTML_FILE=$(echo "$CMD" | python3 -c "
import sys, re
cmd = sys.stdin.read()
for pat in [
    r\"src\s*=\s*['\\\"]?(/home/idarfan/csp/[\w\-]+\.html)\",
    r\"open\(['\\\"]?(/home/idarfan/csp/[\w\-]+\.html)\",
    r\"(/home/idarfan/csp/(?:option-basics-lesson\d+|index|csp-comic|cc-covered-call-lesson)\.html)\",
]:
    m = re.search(pat, cmd)
    if m:
        print(m.group(1))
        break
" 2>/dev/null)

[ -z "$HTML_FILE" ] && exit 0
[ -f "$HTML_FILE" ] || exit 0

HAS_DRAG=$(grep -c 'data-drag-id' "$HTML_FILE" 2>/dev/null || echo 0)
[ "$HAS_DRAG" -gt 0 ] || exit 0

BASENAME=$(basename "$HTML_FILE")
LAY_KEY=$(grep -oP "[l]\d+-layout-v\d+" "$HTML_FILE" 2>/dev/null | head -1)
[ -z "$LAY_KEY" ] && LAY_KEY="layout-key"

python3 -c "
import json, sys
fname, laykey = sys.argv[1], sys.argv[2]
msg = (
    '🚨 [CSP 強制] ' + fname + ' 已修改，必須立即執行 Playwright 交疊檢查\n\n'
    'localStorage key: ' + laykey + '\n\n'
    '必做步驟（不得省略）：\n'
    '1. browser_navigate → http://localhost:8765/' + fname + '\n'
    '2. browser_run_code_unsafe → localStorage.removeItem(\"' + laykey + '\"); location.reload();\n'
    '3. 截圖確認所有 data-drag-id 元素無交疊\n'
    '4. 若有交疊 → 立即 bump localStorage key vN→vN+1 再重複步驟 1-3\n\n'
    '⛔ 禁止在未截圖確認前向用戶報告完成。'
)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': msg
    }
}, ensure_ascii=False))
" "$BASENAME" "$LAY_KEY"
exit 0
HOOK_CONTENT

chmod +x "$HOOK_PATH"
echo "✅ hook 腳本已建立：$HOOK_PATH"

# ── 2. 更新 settings.json ─────────────────────────────────
python3 - "$SETTINGS_PATH" << 'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

new_hook = {
    "matcher": "Bash",
    "hooks": [{
        "type": "command",
        "command": "/home/idarfan/.claude/hooks/post-bash-csp-html-overlap-check.sh",
        "timeout": 10
    }]
}

# 避免重複加入
existing = cfg.get("hooks", {}).get("PostToolUse", [])
for item in existing:
    for h in item.get("hooks", []):
        if "csp-html-overlap" in h.get("command", ""):
            print("⚠️  hook 已存在於 settings.json，略過")
            sys.exit(0)

cfg.setdefault("hooks", {}).setdefault("PostToolUse", []).append(new_hook)

with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)

print("✅ settings.json 已更新")
PYEOF

echo ""
echo "🎉 安裝完成！之後修改 CSP HTML 頁面，Claude 會強制執行 Playwright 交疊檢查。"
