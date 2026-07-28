#!/usr/bin/env python3
import shutil, re

TARGET = '/home/idarfan/csp/option-basics-lesson5.html'
shutil.copy(TARGET, '/tmp/option-basics-lesson5.bak.html')

with open(TARGET, encoding='utf-8') as f:
    html = f.read()

# ── 1. New HTML sections to insert before the outer closing </div> ──────────
NEW_SECTIONS = '''
  <!-- ══ 造市商延伸說明 ══════════════════════════════════════════════════ -->

  <!-- Section 6: 造市商與交易所合約 -->
  <div class="bonus-panel" id="l5-mm-contract" style="margin-top:16px;">
    <div class="tag-row">
      <div style="display:flex;align-items:center;gap:8px;">
        <div class="step-badge" style="background:var(--blue);">6</div>
        <div class="pill-outline chart">MM CONTRACT</div>
      </div>
      <div class="pill chart">造市商與交易所合約 🤝</div>
    </div>

    <div class="ptitle" style="margin-top:14px;">造市商憑什麼能在市場「開店」？</div>
    <div style="font-size:13px;color:var(--muted);margin-top:6px;line-height:1.65;">
      造市商並非想進場就能進場——它必須與交易所簽訂<strong>造市商協議（Market Maker Agreement）</strong>，以「特權換義務」維持市場秩序。
    </div>

    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:16px;">
      <!-- 特權 -->
      <div style="background:var(--green-bg);border:1.5px solid var(--green-bdr);border-radius:var(--r-md);padding:14px 16px;">
        <div style="font-size:11px;font-weight:800;color:var(--green);letter-spacing:1px;text-transform:uppercase;margin-bottom:10px;">✅ 特權（Privileges）</div>
        <div class="bullets">
          <div class="bullet">
            <div class="bullet-num" style="background:var(--green-bg);border-color:var(--green-bdr);color:var(--green);">1</div>
            <span><strong>零手續費</strong>：每筆交易免佣，大幅降低高頻操作成本</span>
          </div>
          <div class="bullet">
            <div class="bullet-num" style="background:var(--green-bg);border-color:var(--green-bdr);color:var(--green);">2</div>
            <span><strong>優先撮合</strong>：相同報價下，造市商訂單比散戶先成交</span>
          </div>
          <div class="bullet">
            <div class="bullet-num" style="background:var(--green-bg);border-color:var(--green-bdr);color:var(--green);">3</div>
            <span><strong>股票出借</strong>：可向交易所借入股票執行 Delta 對沖，無需持有</span>
          </div>
          <div class="bullet">
            <div class="bullet-num" style="background:var(--green-bg);border-color:var(--green-bdr);color:var(--green);">4</div>
            <span><strong>自有訂單流</strong>：可優先看到部分散戶訂單，預判短期供需</span>
          </div>
        </div>
      </div>

      <!-- 義務 -->
      <div style="background:var(--red-bg);border:1.5px solid var(--red-bdr);border-radius:var(--r-md);padding:14px 16px;">
        <div style="font-size:11px;font-weight:800;color:var(--red);letter-spacing:1px;text-transform:uppercase;margin-bottom:10px;">⚠️ 義務（Obligations）</div>
        <div class="bullets">
          <div class="bullet">
            <div class="bullet-num" style="background:var(--red-bg);border-color:var(--red-bdr);color:var(--red);">1</div>
            <span><strong>雙邊連續報價</strong>：必須同時掛出 Bid（買價）與 Ask（賣價），讓市場隨時可交易</span>
          </div>
          <div class="bullet">
            <div class="bullet-num" style="background:var(--red-bg);border-color:var(--red-bdr);color:var(--red);">2</div>
            <span><strong>最大 Spread（價差）限制</strong>：Bid-Ask 不能超過交易所規定上限，通常 &lt; $0.10–$0.30</span>
          </div>
          <div class="bullet">
            <div class="bullet-num" style="background:var(--red-bg);border-color:var(--red-bdr);color:var(--red);">3</div>
            <span><strong>不可單方面撤市</strong>：極端行情下仍須報價，不得因風險過大而直接離場</span>
          </div>
        </div>
      </div>
    </div>

    <div class="warning" style="margin-top:16px;">
      <span>💡</span>
      <span>正是這份合約，讓你每次賣 Put 或執行滾倉時，對面<strong>永遠都有人接</strong>——那就是履行義務的造市商。</span>
    </div>
  </div>

  <!-- Section 7: 商業模式 — 靠 Spread 賺錢 -->
  <div class="bonus-panel" id="l5-mm-spread" style="margin-top:16px;">
    <div class="tag-row">
      <div style="display:flex;align-items:center;gap:8px;">
        <div class="step-badge" style="background:var(--gold);">7</div>
        <div class="pill-outline gold">BUSINESS MODEL</div>
      </div>
      <div class="pill gold">商業模式 — 靠 Spread（價差）賺錢 💰</div>
    </div>

    <div class="ptitle" style="margin-top:14px;">造市商的收入公式很簡單：每次都賺那一點點差價</div>
    <div style="font-size:13px;color:var(--muted);margin-top:6px;line-height:1.65;">
      造市商不賭方向——它只是同時報出買價和賣價，在中間賺取 Spread（價差）。每一筆成交，哪怕只有幾分錢，乘上每天數百萬筆交易就是穩定收入。
    </div>

    <!-- Spread 圖解 -->
    <div style="margin-top:16px;background:#FFFBF4;border:1.5px dashed var(--border);border-radius:var(--r-md);padding:16px 18px;">
      <div style="font-size:12px;font-weight:800;color:var(--muted);letter-spacing:1px;text-transform:uppercase;margin-bottom:12px;">📊 Spread（價差）運作示意</div>
      <div style="display:grid;grid-template-columns:1fr auto 1fr auto 1fr;align-items:center;gap:8px;text-align:center;">
        <!-- 你賣 -->
        <div style="background:var(--blue-bg);border:1.5px solid var(--blue-bdr);border-radius:var(--r-md);padding:10px 8px;">
          <div style="font-size:18px;margin-bottom:4px;">🙋</div>
          <div style="font-size:12px;font-weight:800;color:var(--blue);">你 賣 Put</div>
          <div style="font-size:11px;color:var(--muted);margin-top:4px;">成交價：Bid</div>
          <div style="font-size:20px;font-weight:900;color:var(--ink);margin-top:2px;">$2.00</div>
        </div>
        <div style="font-size:22px;color:var(--muted);">↔</div>
        <!-- 造市商 -->
        <div style="background:var(--gold-bg);border:2px solid var(--gold-bdr);border-radius:var(--r-md);padding:10px 8px;">
          <div style="font-size:18px;margin-bottom:4px;">🏦</div>
          <div style="font-size:12px;font-weight:800;color:var(--gold);">造市商</div>
          <div style="font-size:10px;color:var(--muted);margin-top:4px;">Bid $2.00 / Ask $2.05</div>
          <div style="font-size:13px;font-weight:900;color:var(--green);margin-top:4px;">賺 $0.05 × 100 = <br><span style="font-size:16px;">$5</span></div>
        </div>
        <div style="font-size:22px;color:var(--muted);">↔</div>
        <!-- 下一個買家 -->
        <div style="background:var(--green-bg);border:1.5px solid var(--green-bdr);border-radius:var(--r-md);padding:10px 8px;">
          <div style="font-size:18px;margin-bottom:4px;">🙋</div>
          <div style="font-size:12px;font-weight:800;color:var(--green);">下一個買家</div>
          <div style="font-size:11px;color:var(--muted);margin-top:4px;">成交價：Ask</div>
          <div style="font-size:20px;font-weight:900;color:var(--ink);margin-top:2px;">$2.05</div>
        </div>
      </div>
      <div style="text-align:center;margin-top:12px;font-size:12px;color:var(--muted);">
        Spread（價差）= Ask − Bid = $2.05 − $2.00 = <strong style="color:var(--green);">$0.05 / 股 = $5 / 口</strong>
      </div>
    </div>

    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:14px;">
      <div class="spill">
        <div class="sl">每口 Spread（價差）利潤</div>
        <div class="sv green">$5</div>
      </div>
      <div class="spill">
        <div class="sl">每天交易筆數（大型 MM）</div>
        <div class="sv blue">數百萬筆</div>
      </div>
      <div class="spill">
        <div class="sl">方向性風險</div>
        <div class="sv gold">接近零</div>
      </div>
    </div>

    <div class="warning" style="margin-top:14px;">
      <span>💡</span>
      <span>造市商的利潤與股價漲跌<strong>完全無關</strong>——它只需市場有成交量。這也是為什麼造市商偏好流動性高的標的：成交越多，賺得越多。</span>
    </div>
  </div>

  <!-- Section 8: Delta 對沖實現「無風險」收 Spread -->
  <div class="bonus-panel" id="l5-mm-hedge" style="margin-top:16px;">
    <div class="tag-row">
      <div style="display:flex;align-items:center;gap:8px;">
        <div class="step-badge" style="background:var(--purple);">8</div>
        <div class="pill-outline bonus">DELTA HEDGE</div>
      </div>
      <div class="pill bonus">Delta 對沖 — 讓 Spread（價差）成為「無風險」利潤 🔒</div>
    </div>

    <div class="ptitle" style="margin-top:14px;">造市商如何把方向性風險歸零？</div>
    <div style="font-size:13px;color:var(--muted);margin-top:6px;line-height:1.65;">
      光靠 Spread（價差）還不夠——如果造市商買入的 Put 因為股價大跌而暴漲，Spread 那點收入根本不夠補損。所以造市商在每一筆成交的同時，立刻用股票對沖消除方向風險。以 NOK 滾倉為例：
    </div>

    <!-- NOK Example Flow -->
    <div style="margin-top:16px;">
      <div style="font-size:12px;font-weight:800;color:var(--muted);letter-spacing:0.5px;margin-bottom:10px;">📋 NOK 真實案例：造市商如何對沖你的滾倉</div>
      <div style="display:flex;flex-direction:column;gap:8px;">
        <!-- Step 1 -->
        <div style="display:flex;align-items:flex-start;gap:12px;background:var(--blue-bg);border:1.5px solid var(--blue-bdr);border-radius:var(--r-md);padding:12px 14px;">
          <div style="width:28px;height:28px;background:var(--blue);border-radius:100px;display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:900;color:#fff;flex-shrink:0;">1</div>
          <div>
            <div style="font-size:13px;font-weight:800;color:var(--ink);">你賣出 10口 NOK $14 Put @ $0.30</div>
            <div style="font-size:12px;color:var(--muted);margin-top:3px;">→ 造市商以 Bid 買入，立刻持有 10口 NOK Put，得到負 Delta：<strong style="color:var(--red);">Δ = −0.30 × 10 × 100 = −3,000 Delta</strong></div>
          </div>
        </div>
        <!-- Step 2 -->
        <div style="display:flex;align-items:flex-start;gap:12px;background:var(--gold-bg);border:1.5px solid var(--gold-bdr);border-radius:var(--r-md);padding:12px 14px;">
          <div style="width:28px;height:28px;background:var(--gold);border-radius:100px;display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:900;color:#fff;flex-shrink:0;">2</div>
          <div>
            <div style="font-size:13px;font-weight:800;color:var(--ink);">毫秒內：演算法買入 3,000 股 NOK @ $15.50</div>
            <div style="font-size:12px;color:var(--muted);margin-top:3px;">→ 股票的 Delta = +1.0 × 3,000 = <strong style="color:var(--green);">+3,000 Delta</strong></div>
          </div>
        </div>
        <!-- Step 3 -->
        <div style="display:flex;align-items:flex-start;gap:12px;background:var(--green-bg);border:1.5px solid var(--green-bdr);border-radius:var(--r-md);padding:12px 14px;">
          <div style="width:28px;height:28px;background:var(--green);border-radius:100px;display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:900;color:#fff;flex-shrink:0;">3</div>
          <div>
            <div style="font-size:13px;font-weight:800;color:var(--ink);">Net Delta ≈ 0，方向風險歸零</div>
            <div style="font-size:12px;color:var(--muted);margin-top:3px;">NOK 漲 → 股票賺 / Put 跌，淨損益 ≈ 0 ｜ NOK 跌 → 股票虧 / Put 漲，淨損益 ≈ 0</div>
          </div>
        </div>
        <!-- Step 4 -->
        <div style="display:flex;align-items:flex-start;gap:12px;background:var(--panel-bg);border:2px solid var(--gold-bdr);border-radius:var(--r-md);padding:12px 14px;">
          <div style="font-size:20px;flex-shrink:0;">💰</div>
          <div>
            <div style="font-size:13px;font-weight:800;color:var(--gold);">造市商最終保留：Spread（價差）利潤</div>
            <div style="font-size:12px;color:var(--muted);margin-top:3px;">Ask − Bid = $0.31 − $0.30 = $0.01 × 10口 × 100 = <strong style="color:var(--gold);">$10 淨利</strong>（無論 NOK 漲跌）</div>
          </div>
        </div>
      </div>
    </div>

    <div class="warning" style="margin-top:14px;">
      <span>💡</span>
      <span>造市商每一步對沖都是即時的——當你點下「賣出」的瞬間，它已在另一個市場完成對沖。這叫做<strong>動態 Delta 對沖（Dynamic Delta Hedging）</strong>，是現代造市商的核心技術。</span>
    </div>
  </div>

  <!-- Section 9: 沒有造市商會怎樣 -->
  <div class="bonus-panel" id="l5-mm-nomm" style="margin-top:16px;">
    <div class="tag-row">
      <div style="display:flex;align-items:center;gap:8px;">
        <div class="step-badge" style="background:var(--red);">9</div>
        <div class="pill-outline assign">NO MARKET MAKER</div>
      </div>
      <div class="pill assign">沒有造市商會怎樣？ ⚠️</div>
    </div>

    <div class="ptitle" style="margin-top:14px;">如果造市商消失，期權市場會立刻癱瘓</div>
    <div style="font-size:13px;color:var(--muted);margin-top:6px;line-height:1.65;">
      期權市場的流動性幾乎完全依賴造市商。沒有它們，以下情況會立即發生：
    </div>

    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:16px;">
      <!-- 問題 1 -->
      <div style="background:var(--red-bg);border:1.5px solid var(--red-bdr);border-radius:var(--r-md);padding:14px;">
        <div style="font-size:20px;margin-bottom:6px;">📉</div>
        <div style="font-size:13px;font-weight:800;color:var(--red);margin-bottom:6px;">Bid-Ask Spread（買賣價差）暴漲</div>
        <div style="font-size:12px;color:var(--muted);line-height:1.6;">現在 NOK Put 的 Spread（價差）約 $0.01–$0.05；無造市商時可能超過 <strong>$0.50</strong>，進出成本暴增 10 倍以上</div>
      </div>
      <!-- 問題 2 -->
      <div style="background:var(--red-bg);border:1.5px solid var(--red-bdr);border-radius:var(--r-md);padding:14px;">
        <div style="font-size:20px;margin-bottom:6px;">🚫</div>
        <div style="font-size:13px;font-weight:800;color:var(--red);margin-bottom:6px;">流動性差的期權根本無法成交</div>
        <div style="font-size:12px;color:var(--muted);line-height:1.6;">只有當另一位散戶剛好想做反向交易，你的訂單才能成交——低流動性期權可能掛幾天都等不到對手方</div>
      </div>
      <!-- 問題 3 -->
      <div style="background:var(--red-bg);border:1.5px solid var(--red-bdr);border-radius:var(--r-md);padding:14px;">
        <div style="font-size:20px;margin-bottom:6px;">🔄</div>
        <div style="font-size:13px;font-weight:800;color:var(--red);margin-bottom:6px;">滾倉訂單無法即時執行</div>
        <div style="font-size:12px;color:var(--muted);line-height:1.6;">Roll 需要同時成交買回舊倉 + 開立新倉。沒有造市商，兩筆訂單都可能找不到對手方，滾倉策略完全失效</div>
      </div>
      <!-- 問題 4 -->
      <div style="background:var(--red-bg);border:1.5px solid var(--red-bdr);border-radius:var(--r-md);padding:14px;">
        <div style="font-size:20px;margin-bottom:6px;">⏱️</div>
        <div style="font-size:13px;font-weight:800;color:var(--red);margin-bottom:6px;">只有掌握完美時機的人能交易</div>
        <div style="font-size:12px;color:var(--muted);line-height:1.6;">你賣 Put 需要剛好有人想買 Put；你想平倉需要剛好有人想賣 Put——散戶幾乎不可能配對成功</div>
      </div>
    </div>

    <!-- 總結 -->
    <div style="margin-top:18px;background:var(--gold-bg);border:2px solid var(--gold-bdr);border-radius:var(--r-md);padding:16px 18px;text-align:center;">
      <div style="font-size:12px;font-weight:800;color:var(--gold);letter-spacing:1px;text-transform:uppercase;margin-bottom:8px;">📌 三者關係總結</div>
      <div style="font-size:14px;color:var(--ink);line-height:1.8;">
        造市商以<strong>「法律契約維持市場流動性」</strong>換取<strong>「Spread（價差）利潤」</strong>，<br>
        並透過<strong> Delta 對沖</strong>把方向風險歸零，<br>
        讓你每次開倉、滾倉都能<strong>即時成交</strong>。
      </div>
    </div>
  </div>

'''

# ── 2. TTS entries for new sections ──────────────────────────────────────────
NEW_TTS = """,
    {
      id: 'l5-mm-contract', label: '造市商與交易所合約',
      text: '造市商並非想進場就能進場——它必須與交易所簽訂造市商協議。合約給予造市商四項特權：零手續費，讓高頻操作成本極低；優先撮合，相同報價下造市商訂單比散戶先成交；股票出借，可向交易所借入股票執行 Delta 對沖；以及自有訂單流，可預見部分散戶訂單動向。但特權的代價是三項義務：必須同時掛出買價和賣價持續雙邊報價；買賣價差不能超過交易所規定上限；以及不可在極端行情下單方面撤出市場。正是這份合約，讓你每次賣 Put 或執行滾倉時，對面永遠都有人接。'
    },
    {
      id: 'l5-mm-spread', label: '商業模式：靠 Spread 賺錢',
      text: '造市商的商業模式非常簡單：每筆交易只賺那一點點 Spread，也就是買賣價差。以 NOK Put 為例，Bid 兩元、Ask 兩點零五元：你賣出，造市商以兩元買入；下一個買家以兩點零五元成交，造市商賺零點零五元，乘以一百股等於五元。單筆利潤微薄，但大型造市商每天執行數百萬筆，年度利潤極為可觀。關鍵是造市商的收入與股價方向完全無關，它只需要市場有足夠的成交量。'
    },
    {
      id: 'l5-mm-hedge', label: 'Delta 對沖：無風險收 Spread',
      text: 'Delta 對沖讓造市商把方向性風險歸零。以 NOK 滾倉為例，你賣出十口 NOK 十四美元 Put，Delta 負零點三；造市商買入後立刻持有負三千 Delta 的風險敞口。演算法毫秒內同時買入三千股 NOK 股票，每股 Delta 加一，合計正三千 Delta，和 Put 的負三千精確對沖，Net Delta 歸零。此後無論 NOK 漲跌，股票和 Put 的損益互相抵消，造市商只保留 Spread 利潤。這就是動態 Delta 對沖，是現代造市商的核心技術。'
    },
    {
      id: 'l5-mm-nomm', label: '沒有造市商會怎樣',
      text: '最後來想像一個沒有造市商的期權市場。首先，Bid-Ask Spread 會暴漲，NOK Put 現在買賣價差只有一到五分，沒有造市商時可能超過五毛，進出成本暴增十倍。其次，流動性差的期權根本無法成交，你的訂單需要等另一位散戶剛好想做反向交易，可能掛幾天都等不到。第三，滾倉訂單無法即時執行，Roll 需要同時成交兩筆，沒有造市商兩筆都可能失敗。第四，只有掌握完美時機的人才能交易，散戶幾乎不可能配對成功。總結：造市商以法律契約維持市場流動性換取 Spread 利潤，並透過 Delta 對沖把方向風險歸零，讓你每次開倉、滾倉都能即時成交。'
    }"""

# ── Insert HTML before outer closing </div> ──────────────────────────────────
ANCHOR = '    <div class="warning">\n      <span>💡</span>\n      <span>造市商對你的策略方向毫無意見'
if ANCHOR not in html:
    print('❌ Cannot find HTML anchor')
    exit(1)

# Find the closing of the bonus panel and the outer wrapper
BONUS_END = '''    </div>
  </div>

</div>

<!-- ══ EDIT MODE'''

if BONUS_END not in html:
    print('❌ Cannot find bonus panel end anchor')
    print('Trying alternative...')
    # Find it differently
    idx = html.find('  </div>\n\n</div>\n\n<!-- ══ EDIT MODE')
    if idx == -1:
        idx = html.find('  </div>\n\n</div>\n\n\n<!-- ══ EDIT MODE')
    print('idx:', idx)
    print(repr(html[idx-50:idx+100]))
    exit(1)

NEW_BONUS_END = '''    </div>
  </div>
''' + NEW_SECTIONS + '''
</div>

<!-- ══ EDIT MODE'''

html = html.replace(BONUS_END, NEW_BONUS_END, 1)

# ── Insert TTS entries after l5-bonus entry ───────────────────────────────────
TTS_ANCHOR = "      id: 'l5-bonus', label: '真實案例與五大啟示',"
if TTS_ANCHOR not in html:
    print('❌ Cannot find TTS anchor')
    exit(1)

# Find the end of the l5-bonus entry (closing brace + newline)
idx = html.find(TTS_ANCHOR)
# Find the closing } of this entry
end_idx = html.find('\n    }', idx) + len('\n    }')
# Insert after that
html = html[:end_idx] + NEW_TTS + html[end_idx:]

with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(html)

print('✅ Done! New sections and TTS entries added to lesson5')
print('Line count:', len(html.splitlines()))
