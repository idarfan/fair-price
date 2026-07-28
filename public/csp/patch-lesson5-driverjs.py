#!/usr/bin/env python3
import shutil

SRC  = '/home/idarfan/csp/option-basics-lesson7.html'
DEST = '/home/idarfan/csp/option-basics-lesson5.html'
shutil.copy(DEST, '/tmp/option-basics-lesson5.bak4.html')

# Extract Driver.js block (style + script) from lesson7
with open(SRC, encoding='utf-8') as f:
    src_lines = f.readlines()

driver_block_lines = []
in_block = False
for line in src_lines:
    if '<style id="driver-css">' in line:
        in_block = True
    if in_block:
        driver_block_lines.append(line)
    if in_block and '</script>' in line and len(driver_block_lines) > 5:
        # Check we got past the driver-js script tag
        joined = ''.join(driver_block_lines)
        if 'driver-js' in joined:
            break

DRIVER_BLOCK = ''.join(driver_block_lines)

with open(DEST, encoding='utf-8') as f:
    html = f.read()

# ── 1. Insert Driver.js block before </head> ─────────────────────────────────
assert '</head>' in html, '❌ </head> not found'
assert 'driver-css' not in html, '❌ Driver.js already present'
html = html.replace('</head>', DRIVER_BLOCK + '</head>', 1)

# ── 2. Add IDs to target elements in l5-mm-hedge ────────────────────────────
# Step boxes already have inline styles; add id attributes
html = html.replace(
    '<div style="display:flex;align-items:flex-start;gap:12px;background:var(--blue-bg);border:1.5px solid var(--blue-bdr);border-radius:var(--r-md);padding:12px 14px;">\n          <div style="width:28px;height:28px;background:var(--blue)',
    '<div id="dh-step1" style="display:flex;align-items:flex-start;gap:12px;background:var(--blue-bg);border:1.5px solid var(--blue-bdr);border-radius:var(--r-md);padding:12px 14px;">\n          <div style="width:28px;height:28px;background:var(--blue)',
    1
)
html = html.replace(
    '<div style="display:flex;align-items:flex-start;gap:12px;background:var(--gold-bg);border:1.5px solid var(--gold-bdr);border-radius:var(--r-md);padding:12px 14px;">\n          <div style="width:28px;height:28px;background:var(--gold)',
    '<div id="dh-step2" style="display:flex;align-items:flex-start;gap:12px;background:var(--gold-bg);border:1.5px solid var(--gold-bdr);border-radius:var(--r-md);padding:12px 14px;">\n          <div style="width:28px;height:28px;background:var(--gold)',
    1
)
html = html.replace(
    '<div style="display:flex;align-items:flex-start;gap:12px;background:var(--green-bg);border:1.5px solid var(--green-bdr);border-radius:var(--r-md);padding:12px 14px;">\n          <div style="width:28px;height:28px;background:var(--green)',
    '<div id="dh-step3" style="display:flex;align-items:flex-start;gap:12px;background:var(--green-bg);border:1.5px solid var(--green-bdr);border-radius:var(--r-md);padding:12px 14px;">\n          <div style="width:28px;height:28px;background:var(--green)',
    1
)
html = html.replace(
    '<div style="display:flex;align-items:flex-start;gap:12px;background:var(--panel-bg);border:2px solid var(--gold-bdr);border-radius:var(--r-md);padding:12px 14px;">\n          <div style="font-size:20px;flex-shrink:0;">💰</div>',
    '<div id="dh-spread" style="display:flex;align-items:flex-start;gap:12px;background:var(--panel-bg);border:2px solid var(--gold-bdr);border-radius:var(--r-md);padding:12px 14px;">\n          <div style="font-size:20px;flex-shrink:0;">💰</div>',
    1
)
html = html.replace(
    '<div style="font-size:13px;font-weight:800;color:var(--ink);margin-bottom:12px;">📐 為什麼是 300 股，而不是 1,000 股？</div>',
    '<div id="dh-why300-title" style="font-size:13px;font-weight:800;color:var(--ink);margin-bottom:12px;">📐 為什麼是 300 股，而不是 1,000 股？</div>',
    1
)
html = html.replace(
    '<div style="background:var(--blue-bg);border:1.5px solid var(--blue-bdr);border-radius:var(--r-md);padding:13px 15px;margin-bottom:12px;">\n        <div style="font-size:12px;font-weight:800;color:var(--blue);margin-bottom:8px;">💡 Delta 的真正含義</div>',
    '<div id="dh-delta-meaning" style="background:var(--blue-bg);border:1.5px solid var(--blue-bdr);border-radius:var(--r-md);padding:13px 15px;margin-bottom:12px;">\n        <div style="font-size:12px;font-weight:800;color:var(--blue);margin-bottom:8px;">💡 Delta 的真正含義</div>',
    1
)
html = html.replace(
    '<div style="font-size:12px;font-weight:800;color:var(--muted);margin-bottom:8px;">📊 Delta 會隨股價移動，對沖持股數也要跟著調整</div>',
    '<div id="dh-dynamic-title" style="font-size:12px;font-weight:800;color:var(--muted);margin-bottom:8px;">📊 Delta 會隨股價移動，對沖持股數也要跟著調整</div>',
    1
)

# ── 3. Add tour button inside l5-mm-hedge, after the section title ───────────
OLD_HEDGE_TITLE = '''    <div class="ptitle" style="margin-top:14px;">造市商如何把方向性風險歸零？</div>'''
NEW_HEDGE_TITLE = '''    <div class="ptitle" style="margin-top:14px;">造市商如何把方向性風險歸零？</div>
    <div style="margin-top:8px;">
      <button onclick="startDeltaHedgeTour()" style="background:var(--blue);color:#fff;border:none;border-radius:100px;padding:7px 18px;font-size:12px;font-weight:700;cursor:pointer;font-family:inherit;">🎯 啟動 Delta 對沖導覽</button>
    </div>'''
assert OLD_HEDGE_TITLE in html, '❌ hedge title anchor not found'
html = html.replace(OLD_HEDGE_TITLE, NEW_HEDGE_TITLE, 1)

# ── 4. Add Driver.js tour script before closing </script> of TTS block ───────
TOUR_SCRIPT = '''
  // ── Driver.js: Dynamic Delta Hedging 導覽 ──────────────────────────────
  window.startDeltaHedgeTour = function () {
    var driverObj = window.driver.js.driver({
      showProgress: true,
      nextBtnText: '下一步 →',
      prevBtnText: '← 上一步',
      doneBtnText: '完成 ✓',
      steps: [
        {
          element: '#dh-step1',
          popover: {
            title: '① 你賣出 Put，MM 接單',
            description: '你賣出 10口 NOK $14 Put，每口 Delta = −0.30。<br><br>造市商以 <strong>Bid 價</strong>買入，立刻持有：<br>10口 × 100股 × 0.30 = <strong style="color:#D04040;">−300 Delta</strong> 的曝險。<br><br>Delta 為負代表：股價每跌 $1，MM 持有的 Put 組合就<strong>獲利 $300</strong>，這是方向性風險。',
            side: 'bottom', align: 'start'
          }
        },
        {
          element: '#dh-step2',
          popover: {
            title: '② 毫秒內：買入 300 股對沖',
            description: '演算法立刻在股票市場買入 <strong>300 股</strong> NOK。<br><br>每股股票 Delta = +1.0，所以：<br>300股 × 1.0 = <strong style="color:#2E9E52;">+300 Delta</strong><br><br>為什麼是 300 股？因為 Put 的曝險只有 300 Delta，買 300 股剛好對沖，<strong>不多也不少</strong>。',
            side: 'bottom', align: 'start'
          }
        },
        {
          element: '#dh-step3',
          popover: {
            title: '③ Net Delta ≈ 0，方向風險歸零',
            description: '−300（Put）＋ +300（股票）= <strong>0</strong><br><br>此後無論 NOK 漲跌：<br>• NOK 漲 → 股票賺 / Put 跌 → 淨損益 ≈ 0<br>• NOK 跌 → 股票虧 / Put 漲 → 淨損益 ≈ 0<br><br>造市商<strong>不賭方向</strong>，兩種情況都不虧。',
            side: 'top', align: 'start'
          }
        },
        {
          element: '#dh-spread',
          popover: {
            title: '④ 最終保留：Spread（價差）利潤',
            description: '對沖消除方向風險後，造市商唯一保留的就是 <strong>Spread（價差）</strong>：<br><br>Ask − Bid = $0.31 − $0.30 = <strong style="color:#D4900A;">$0.01 × 10口 × 100 = $10 淨利</strong><br><br>這筆利潤與 NOK 漲跌<strong>完全無關</strong>，每次成交都穩賺。',
            side: 'top', align: 'start'
          }
        },
        {
          element: '#dh-why300-title',
          popover: {
            title: '⑤ 為什麼不買 1,000 股？',
            description: '1,000 股 = 10口 × 100股，是合約的全部標的股數。<br><br>但 Put 的 Delta 只有 −0.30，意思是它<strong>只等效做空了 300 股</strong>，而不是 1,000 股。<br><br>如果買 1,000 股對沖：<br>NOK 跌 $1 → Put 賺 $300，股票虧 $1,000 → <strong style="color:#D04040;">淨虧 $700</strong><br><br>買太多股票反而製造相反方向的風險！',
            side: 'top', align: 'start'
          }
        },
        {
          element: '#dh-delta-meaning',
          popover: {
            title: '⑥ Delta = 等效股票數量',
            description: 'Delta −0.30 的直覺解釋：<br><br><em>「這張 Put 的行為，等同於做空了 30 股股票」</em><br><br>所以 10口 × 30股等效 = <strong>300 股等效曝險</strong>。<br><br>對沖就是把這 300 股等效曝險，用買入 300 股真實股票來抵銷。',
            side: 'left', align: 'start'
          }
        },
        {
          element: '#dh-dynamic-title',
          popover: {
            title: '⑦ Delta 是動態的',
            description: 'Delta 不是固定的——股價移動，Delta 就跟著變。<br><br>• OTM（$15）→ Delta −0.20 → 需持 <strong>200 股</strong><br>• ATM（$14）→ Delta −0.50 → 需持 <strong>500 股</strong><br>• ITM（$12）→ Delta −0.85 → 需持 <strong>850 股</strong><br><br>造市商的演算法每秒都在計算，隨時增減持股，這就是「<strong>動態</strong> Delta 對沖」的意思。',
            side: 'top', align: 'start'
          }
        }
      ]
    });
    document.getElementById('l5-mm-hedge').scrollIntoView({ behavior: 'smooth', block: 'start' });
    setTimeout(function () { driverObj.drive(); }, 400);
  };

'''

# Insert before the closing }()); of TTS IIFE
OLD_IIFE_END = '\n}());\n</script>\n\n</body>'
assert OLD_IIFE_END in html, '❌ IIFE end anchor not found'
html = html.replace(OLD_IIFE_END, TOUR_SCRIPT + '\n}());\n</script>\n\n</body>', 1)

with open(DEST, 'w', encoding='utf-8') as f:
    f.write(html)

print('✅ Done. Lines:', len(html.splitlines()))
checks = ['driver-css', 'driver-js', 'startDeltaHedgeTour', 'dh-step1', 'dh-step2',
          'dh-step3', 'dh-spread', 'dh-delta-meaning', 'dh-dynamic-title',
          '啟動 Delta 對沖導覽', 'dh-why300-title']
for c in checks:
    print('✓' if c in html else '✗ MISSING:', c)
