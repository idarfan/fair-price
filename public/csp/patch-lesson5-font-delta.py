#!/usr/bin/env python3
import shutil

TARGET = '/home/idarfan/csp/option-basics-lesson5.html'
shutil.copy(TARGET, '/tmp/option-basics-lesson5.bak3.html')

with open(TARGET, encoding='utf-8') as f:
    html = f.read()

# ── 1. Add A+/A− buttons to TTS bar ────────────────────────────────────────
OLD_TTS_BAR_END = '''  <select id="tts-speed" title="語速" onchange="ttsSetRate(this.value)">
    <option value="0.7">慢速 0.7×</option>
    <option value="0.9" selected>正常 0.9×</option>
    <option value="1.1">快速 1.1×</option>
    <option value="1.3">很快 1.3×</option>
  </select>
</div>'''

NEW_TTS_BAR_END = '''  <select id="tts-speed" title="語速" onchange="ttsSetRate(this.value)">
    <option value="0.7">慢速 0.7×</option>
    <option value="0.9" selected>正常 0.9×</option>
    <option value="1.1">快速 1.1×</option>
    <option value="1.3">很快 1.3×</option>
  </select>
  <div class="tts-sep"></div>
  <button class="tts-btn" onclick="adjustPageFont(-1)" style="padding:4px 9px;font-size:11px;font-weight:900;" title="縮小字體">A−</button>
  <button class="tts-btn" onclick="adjustPageFont(1)"  style="padding:4px 9px;font-size:11px;font-weight:900;" title="放大字體">A+</button>
</div>'''

assert OLD_TTS_BAR_END in html, '❌ TTS bar anchor not found'
html = html.replace(OLD_TTS_BAR_END, NEW_TTS_BAR_END, 1)

# ── 2. Add font zoom JS before SCRIPT array ─────────────────────────────────
OLD_SCRIPT_START = '''(function () {
  var SCRIPT = ['''

NEW_SCRIPT_START = '''(function () {
  var _fontZoom = parseFloat(localStorage.getItem('l5-font-zoom') || '1');
  var _fontBaseMap = new WeakMap();
  function applyFontZoom() {
    document.querySelectorAll('.page *').forEach(function (el) {
      if (!_fontBaseMap.has(el)) {
        _fontBaseMap.set(el, parseFloat(window.getComputedStyle(el).fontSize) || 14);
      }
      el.style.fontSize = (_fontBaseMap.get(el) * _fontZoom) + 'px';
    });
  }
  window.adjustPageFont = function (delta) {
    _fontZoom = Math.max(0.7, Math.min(2.0, parseFloat((_fontZoom + delta * 0.1).toFixed(2))));
    applyFontZoom();
    localStorage.setItem('l5-font-zoom', _fontZoom);
  };
  window.addEventListener('load', function () { if (_fontZoom !== 1) applyFontZoom(); });

  var SCRIPT = ['''

assert OLD_SCRIPT_START in html, '❌ SCRIPT array anchor not found'
html = html.replace(OLD_SCRIPT_START, NEW_SCRIPT_START, 1)

# ── 3. Add Delta explanation content inside l5-mm-hedge ─────────────────────
DELTA_EXPLANATION = '''
    <!-- Delta 原理深入說明 -->
    <div style="margin-top:18px;">
      <div style="font-size:13px;font-weight:800;color:var(--ink);margin-bottom:12px;">📐 為什麼是 300 股，而不是 1,000 股？</div>

      <!-- Why not 1000 shares table -->
      <div style="overflow-x:auto;margin-bottom:14px;">
        <table style="width:100%;border-collapse:collapse;font-size:12.5px;">
          <thead>
            <tr style="background:var(--ink);color:#FFF9F0;">
              <th style="padding:8px 12px;text-align:left;border-radius:6px 0 0 0;">情境</th>
              <th style="padding:8px 12px;text-align:right;">Put 獲利（NOK 跌 $1）</th>
              <th style="padding:8px 12px;text-align:right;">股票損失</th>
              <th style="padding:8px 12px;text-align:right;border-radius:0 6px 0 0;">淨損益</th>
            </tr>
          </thead>
          <tbody>
            <tr style="background:var(--red-bg);">
              <td style="padding:8px 12px;border-bottom:1px solid var(--border);">買 1,000 股對沖</td>
              <td style="padding:8px 12px;text-align:right;border-bottom:1px solid var(--border);color:var(--green);font-weight:700;">+$300</td>
              <td style="padding:8px 12px;text-align:right;border-bottom:1px solid var(--border);color:var(--red);font-weight:700;">−$1,000</td>
              <td style="padding:8px 12px;text-align:right;border-bottom:1px solid var(--border);color:var(--red);font-weight:800;">−$700 ❌</td>
            </tr>
            <tr style="background:var(--green-bg);">
              <td style="padding:8px 12px;">買 300 股對沖</td>
              <td style="padding:8px 12px;text-align:right;color:var(--green);font-weight:700;">+$300</td>
              <td style="padding:8px 12px;text-align:right;color:var(--red);font-weight:700;">−$300</td>
              <td style="padding:8px 12px;text-align:right;color:var(--green);font-weight:800;">$0 ✅</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- What Delta means -->
      <div style="background:var(--blue-bg);border:1.5px solid var(--blue-bdr);border-radius:var(--r-md);padding:13px 15px;margin-bottom:12px;">
        <div style="font-size:12px;font-weight:800;color:var(--blue);margin-bottom:8px;">💡 Delta 的真正含義</div>
        <div style="font-size:12.5px;color:var(--ink);line-height:1.75;">
          Delta <strong>−0.30</strong> 代表：<em>「這張 Put 的行為，等同於你做空了 30 股股票」</em>。<br>
          每當 NOK 漲 $1，這張 Put 就跌 $0.30（Put 是看跌的，股票漲對 Put 不利）。<br>
          10口 × 100股 × 0.30 = <strong>300 股的等效曝險</strong>，所以只需買 300 股來對沖，多買反而製造相反方向的風險。
        </div>
      </div>

      <!-- Dynamic Delta table -->
      <div style="font-size:12px;font-weight:800;color:var(--muted);margin-bottom:8px;">📊 Delta 會隨股價移動，對沖持股數也要跟著調整</div>
      <div style="overflow-x:auto;">
        <table style="width:100%;border-collapse:collapse;font-size:12.5px;">
          <thead>
            <tr style="background:rgba(42,26,14,0.08);">
              <th style="padding:7px 12px;text-align:left;border-bottom:2px solid var(--border);">NOK 股價</th>
              <th style="padding:7px 12px;text-align:center;border-bottom:2px solid var(--border);">狀態</th>
              <th style="padding:7px 12px;text-align:right;border-bottom:2px solid var(--border);">Put Delta</th>
              <th style="padding:7px 12px;text-align:right;border-bottom:2px solid var(--border);">需持有股票</th>
            </tr>
          </thead>
          <tbody>
            <tr style="border-bottom:1px solid var(--border);">
              <td style="padding:7px 12px;font-weight:700;">$15（遠 OTM）</td>
              <td style="padding:7px 12px;text-align:center;"><span style="background:var(--green-bg);color:var(--green);border-radius:100px;padding:2px 8px;font-size:11px;font-weight:700;">OTM</span></td>
              <td style="padding:7px 12px;text-align:right;color:var(--muted);">−0.20</td>
              <td style="padding:7px 12px;text-align:right;font-weight:700;">200 股</td>
            </tr>
            <tr style="border-bottom:1px solid var(--border);background:var(--gold-bg);">
              <td style="padding:7px 12px;font-weight:700;">$14（接近 ATM）</td>
              <td style="padding:7px 12px;text-align:center;"><span style="background:var(--gold-bg);color:var(--gold);border-radius:100px;padding:2px 8px;font-size:11px;font-weight:700;">ATM</span></td>
              <td style="padding:7px 12px;text-align:right;color:var(--gold);font-weight:800;">−0.50</td>
              <td style="padding:7px 12px;text-align:right;font-weight:800;color:var(--gold);">500 股</td>
            </tr>
            <tr>
              <td style="padding:7px 12px;font-weight:700;">$12（深度 ITM）</td>
              <td style="padding:7px 12px;text-align:center;"><span style="background:var(--red-bg);color:var(--red);border-radius:100px;padding:2px 8px;font-size:11px;font-weight:700;">ITM</span></td>
              <td style="padding:7px 12px;text-align:right;color:var(--red);">−0.85</td>
              <td style="padding:7px 12px;text-align:right;font-weight:700;">850 股</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div style="font-size:11.5px;color:var(--muted);margin-top:7px;line-height:1.6;">
        這就是為什麼叫「<strong>動態</strong> Delta 對沖」——股價每動一下，Delta 就變，造市商的演算法就要立刻增減持股，不是買一次就不管。
      </div>
    </div>

'''

# Insert before the closing warning of l5-mm-hedge
OLD_HEDGE_END = '''    <div class="warning" style="margin-top:14px;">
      <span>💡</span>
      <span>造市商每一步對沖都是即時的'''

NEW_HEDGE_END = DELTA_EXPLANATION + '''    <div class="warning" style="margin-top:14px;">
      <span>💡</span>
      <span>造市商每一步對沖都是即時的'''

assert OLD_HEDGE_END in html, '❌ hedge section end anchor not found'
html = html.replace(OLD_HEDGE_END, NEW_HEDGE_END, 1)

with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(html)

print('✅ Done')
print('Lines:', len(html.splitlines()))

# Verify
c = open(TARGET).read()
checks = ['adjustPageFont', 'l5-font-zoom', 'applyFontZoom', 'WeakMap',
          'A−', 'A+', '為什麼是 300 股', '買 1,000 股對沖', '買 300 股對沖',
          'Delta 的真正含義', '動態 Delta 對沖']
for ch in checks:
    print('✓' if ch in c else '✗ MISSING:', ch)
