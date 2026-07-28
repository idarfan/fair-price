"""
第10課 Tooltip 測試
測試項目：
  1. 滑鼠移入 td[data-side="ask"] → popover 出現，標題含「ask」
  2. 滑鼠移入 td[data-side="bid"] → popover 內容切換
  3. 滑鼠移入 td[data-side="mid"] → popover 含「mid」
  4. 滑鼠離開 td 與 popover → popover 消失
  5. 拖曳 popover → 位置更新並存入 localStorage
執行：python3 tests/test_l10_tooltip.py
      （需先啟動 http server：python3 -m http.server 8765 --directory /home/idarfan/csp）
"""
import sys, time
from playwright.sync_api import sync_playwright, expect

BASE = "http://localhost:8765/option-basics-lesson10.html"
PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"

results = []

def check(name, ok, detail=""):
    tag = PASS if ok else FAIL
    print(f"  [{tag}] {name}" + (f" — {detail}" if detail else ""))
    results.append(ok)

def hover_td(page, side):
    """用 dispatchEvent 觸發 mouseover（避免 page.hover() 偶發 scroll 問題）"""
    page.evaluate(f"""
        const td = document.querySelector('td[data-side="{side}"]');
        if (td) td.dispatchEvent(new MouseEvent('mouseover', {{bubbles:true, clientX:200, clientY:200}}));
    """)
    page.wait_for_timeout(350)

def leave_all(page):
    """模擬滑鼠移到頁面角落，觸發 watcher 關閉 tooltip"""
    page.evaluate("""
        document.dispatchEvent(new MouseEvent('mousemove', {bubbles:true, clientX:5, clientY:5}));
    """)
    page.wait_for_timeout(250)

def get_popover(page):
    return page.query_selector(".driver-popover.leaps-popover")

def run_tests(page):
    print("\n── 上傳假資料以產生 td[data-side] ──")
    # 注入假資料到 IndexedDB，讓頁面顯示分析表格
    page.evaluate("""async () => {
        const rec = {
            id: 'test-001',
            symbol: 'AAPL',
            date: '2026-06-20',
            uploadedAt: '2026-06-20T00:00:00Z',
            rows: [
                {Type:'Call', Strike:'200', Expires:'2026-07-18', DTE:'28', Trade:'3.50',
                 Size:'10', Side:'ask', Premium:'35000', Time:'09:32', expType:'M'},
                {Type:'Put',  Strike:'190', Expires:'2026-07-18', DTE:'28', Trade:'2.10',
                 Size:'5',  Side:'bid', Premium:'10500', Time:'10:15', expType:'M'},
                {Type:'Call', Strike:'205', Expires:'2026-07-25', DTE:'35', Trade:'1.80',
                 Size:'8',  Side:'mid', Premium:'14400', Time:'11:00', expType:'W'},
            ]
        };
        const db = await new Promise((res,rej)=>{
            const r=indexedDB.open('l10-flow-db',1);
            r.onupgradeneeded=e=>e.target.result.createObjectStore('flow-records',{keyPath:'id'});
            r.onsuccess=e=>res(e.target.result);
            r.onerror=e=>rej(e);
        });
        await new Promise((res,rej)=>{
            const tx=db.transaction('flow-records','readwrite');
            tx.objectStore('flow-records').put(rec);
            tx.oncomplete=res; tx.onerror=rej;
        });
    }""")
    page.reload(wait_until="domcontentloaded")
    page.wait_for_timeout(1200)

    # ── T1：ask tooltip 出現 ──
    print("\n── T1：ask tooltip ──")
    hover_td(page, "ask")
    pw = get_popover(page)
    check("popover 出現", pw is not None)
    if pw:
        title = pw.query_selector(".driver-popover-title")
        check("標題含 'ask'", title and "ask" in (title.inner_text() or "").lower(),
              title.inner_text() if title else "no title")

    # ── T2：bid tooltip 切換 ──
    print("\n── T2：bid tooltip ──")
    hover_td(page, "bid")
    pw = get_popover(page)
    check("popover 仍存在", pw is not None)
    if pw:
        title = pw.query_selector(".driver-popover-title")
        check("標題含 'bid'", title and "bid" in (title.inner_text() or "").lower(),
              title.inner_text() if title else "no title")

    # ── T3：mid tooltip ──
    print("\n── T3：mid tooltip ──")
    hover_td(page, "mid")
    pw = get_popover(page)
    check("popover 仍存在", pw is not None)
    if pw:
        title = pw.query_selector(".driver-popover-title")
        check("標題含 'mid'", title and "mid" in (title.inner_text() or "").lower(),
              title.inner_text() if title else "no title")

    # ── T4：離開後 popover 消失 ──
    print("\n── T4：離開後 popover 消失 ──")
    leave_all(page)
    pw = get_popover(page)
    check("popover 消失", pw is None or pw.get_attribute("style", "") == "display: none;",
          "still visible" if pw else "gone")

    # ── T5：拖曳位置存 localStorage ──
    print("\n── T5：拖曳儲存位置 ──")
    hover_td(page, "ask")
    page.wait_for_timeout(400)
    pw = get_popover(page)
    if pw:
        # Driver.js 在 document capture phase 攔截直接對 pw 發的 mousedown
        # （stopImmediatePropagation 阻止事件到達 pw 的 makeDraggable listener）
        # 解法：對 description 子元素發 mousedown — Driver.js 判斷 desc.contains(target)=true
        # → t(w)=false → 不 stop，事件正常 bubble 到 pw
        page.evaluate("""() => {
            const pw = document.querySelector('.driver-popover.leaps-popover');
            if (!pw) return;
            const desc = pw.querySelector('.driver-popover-description');
            const r = pw.getBoundingClientRect();
            const cx = r.left + r.width / 2, cy = r.top + 10;
            desc.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, button:0, clientX:cx, clientY:cy}));
            document.dispatchEvent(new MouseEvent('mousemove', {bubbles:true, clientX:cx+80, clientY:cy+60}));
            document.dispatchEvent(new MouseEvent('mouseup',   {bubbles:true, clientX:cx+80, clientY:cy+60}));
        }""")
        page.wait_for_timeout(400)
        pos = page.evaluate("() => { try { return JSON.parse(localStorage.getItem('l10-tip-pos')); } catch(e) { return null; } }")
        check("localStorage l10-tip-pos 已寫入", pos is not None and "t" in pos and "l" in pos,
              str(pos))
    else:
        check("拖曳前 popover 存在", False, "popover 未出現")

with sync_playwright() as pw_ctx:
    browser = pw_ctx.chromium.connect_over_cdp("http://localhost:9222")
    ctx = browser.contexts[0] if browser.contexts else browser.new_context()
    page = ctx.new_page()

    page.route("**/*.woff*", lambda r: r.abort())
    page.route("**/*.woff2*", lambda r: r.abort())
    page.goto(BASE, wait_until="domcontentloaded")
    page.evaluate("localStorage.removeItem('l10-layout-v3')")
    page.wait_for_timeout(600)

    try:
        run_tests(page)
    finally:
        page.close()

total = len(results)
passed = sum(results)
print(f"\n{'='*40}")
print(f"結果：{passed}/{total} 通過" + (" ✓" if passed == total else " ✗"))
sys.exit(0 if passed == total else 1)
