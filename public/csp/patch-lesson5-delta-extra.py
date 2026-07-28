#!/usr/bin/env python3
import shutil

TARGET = '/home/idarfan/csp/option-basics-lesson5.html'
shutil.copy(TARGET, '/tmp/option-basics-lesson5.bak5.html')

with open(TARGET, encoding='utf-8') as f:
    html = f.read()

NEW_CONTENT = '''      </div>
    </div>

      <!-- 延伸推論：你的 Delta 決定持股數 -->
      <div style="margin-top:16px;">
        <div style="font-size:13px;font-weight:800;color:var(--ink);margin-bottom:10px;">🔗 你的 CSP Delta 決定造市商要持有多少股</div>
        <div style="overflow-x:auto;margin-bottom:14px;">
          <table style="width:100%;border-collapse:collapse;font-size:12.5px;">
            <thead>
              <tr style="background:var(--ink);color:#FFF9F0;">
                <th style="padding:8px 12px;text-align:left;border-radius:6px 0 0 0;">你賣的 CSP 類型</th>
                <th style="padding:8px 12px;text-align:right;">Put Delta</th>
                <th style="padding:8px 12px;text-align:right;border-radius:0 6px 0 0;">造市商需買入股票（10口）</th>
              </tr>
            </thead>
            <tbody>
              <tr style="border-bottom:1px solid var(--border);">
                <td style="padding:8px 12px;">遠 OTM（履約價遠低於股價）</td>
                <td style="padding:8px 12px;text-align:right;color:var(--muted);">−0.10</td>
                <td style="padding:8px 12px;text-align:right;font-weight:700;">100 股</td>
              </tr>
              <tr style="border-bottom:1px solid var(--border);background:#F5F8FF;">
                <td style="padding:8px 12px;">常用 CSP（Delta −0.20 ～ −0.30）</td>
                <td style="padding:8px 12px;text-align:right;color:var(--blue);font-weight:700;">−0.25</td>
                <td style="padding:8px 12px;text-align:right;font-weight:700;color:var(--blue);">250 股</td>
              </tr>
              <tr style="border-bottom:1px solid var(--border);background:var(--gold-bg);">
                <td style="padding:8px 12px;">接近 ATM</td>
                <td style="padding:8px 12px;text-align:right;color:var(--gold);font-weight:800;">−0.50</td>
                <td style="padding:8px 12px;text-align:right;font-weight:800;color:var(--gold);">500 股</td>
              </tr>
              <tr>
                <td style="padding:8px 12px;">深度 ITM</td>
                <td style="padding:8px 12px;text-align:right;color:var(--red);">−0.85</td>
                <td style="padding:8px 12px;text-align:right;font-weight:700;">850 股</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div style="font-size:12.5px;font-weight:800;color:var(--muted);margin-bottom:8px;">💡 兩個重要推論</div>
        <div class="bullets">
          <div class="bullet">
            <div class="bullet-num">1</div>
            <span><strong>你的 Delta 越接近 ATM（−0.50），造市商對沖成本越高</strong>——它要持有更多股票、調整越頻繁。這也是 ATM 附近 Bid-Ask Spread（價差）往往比遠 OTM 稍寬的原因之一。選 Delta −0.20 ～ −0.30 的 CSP，除了勝率較高，進出的 Spread 也更窄，成本更低。</span>
          </div>
          <div class="bullet">
            <div class="bullet-num">2</div>
            <span><strong>當你的 CSP 從 OTM 跌進 ITM（股價下跌），Delta 從 −0.20 變成 −0.80</strong>——造市商必須不斷加買股票補足對沖（例如從 200 股追到 800 股）。這些追買動作對股價會產生微小的支撐效果，也是為什麼 ATM 附近期權到期日前股價常有「磁吸」現象。</span>
          </div>
        </div>
      </div>

    <div class="warning" style="margin-top:14px;">
      <span>💡</span>
      <span>造市商每一步對沖都是即時的'''

OLD_ANCHOR = '''      </div>
    </div>

    <div class="warning" style="margin-top:14px;">
      <span>💡</span>
      <span>造市商每一步對沖都是即時的'''

assert OLD_ANCHOR in html, '❌ anchor not found'
html = html.replace(OLD_ANCHOR, NEW_CONTENT, 1)

with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(html)

print('✅ Done. Lines:', len(html.splitlines()))
c = open(TARGET).read()
checks = ['你的 CSP Delta 決定造市商要持有多少股', '兩個重要推論', '磁吸']
for ch in checks:
    print('✓' if ch in c else '✗ MISSING:', ch)
