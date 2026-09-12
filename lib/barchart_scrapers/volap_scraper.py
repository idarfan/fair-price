"""
Barchart Volume Profile (VOLAP) scraper — CDP direct WebSocket, no Playwright.

不是抓 canvas，也不自己分箱：Barchart 的 interactive-chart 把 VOLAP 指標算好的
結果掛在頁面 JS 物件上，POC 與 Value Area 都是它自己算的，直接讀就好。
存取路徑見 reference_barchart_volap_dom 記憶。

三個必須處理的前提（每一條都實測踩過）：
  1. VOLAP 的 periodType 是 "VisibleScreen"——結果依畫面範圍而變，
     所以抓之前一定要把圖固定到 period.1Y / CHART.DAILY，抓完再切回原設定。
  2. 分頁在背景時 VOLAP 不會重算。aggregation 會正確變成 DAILY，但 boxes 永遠是
     空陣列（實測等 40 秒也不會好）。prepare_page 已經會 activate_target。
  3. 重算期間 boxes 是 []，直接讀 boxes[0].min 會丟例外，只能輪詢狀態。

Usage: python3 volap_scraper.py SHOP
Output: JSON to stdout
"""
import asyncio
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from cdp_helper import prepare_page, cdp_eval, activate_target


TARGET_PATH        = "interactive-chart"
TARGET_PERIOD_KEY  = "period.1Y"
TARGET_AGGREGATION = "CHART.DAILY"

# 重算輪詢：每 3 秒看一次，最多 60 秒。實測前景分頁約 5 秒就好，
# 60 秒是給冷啟動（剛導航完、資料還在下載）的餘裕。
POLL_INTERVAL_S = 3
POLL_TIMEOUT_S  = 60
# prepare_page 有可能剛重新導航過分頁，圖表元件要幾秒才建得起來。
CHART_READY_TIMEOUT_S = 45


# --- 頁面內腳本 -------------------------------------------------------------
# 共用的 plot 取得邏輯。**每一層都回一個具名狀態，絕不回 null。**
#
# 一開始這裡是 `return null`，結果踩到：prepare_page 喚醒分頁時第一次 eval 逾時
# → 它以為 URL 不對就重新導航 → 圖表還沒建好 → 這裡回 null
# → 被誤判成 barchart_session_expired。「還沒建好」跟「沒登入」是完全不同的兩件事，
# 前者該等，後者該叫使用者去登入，混在一起會讓人白跑一趟登入流程。
_PLOT_JS = """
  const w = document.querySelector('interactive-chart-widget');
  if (!w || !w._panel) return {state: 'no_widget'};
  const charts = w._panel.chartService && w._panel.chartService._feed
               && w._panel.chartService._feed.charts;
  if (!charts || !charts.size) return {state: 'no_chart'};
  const presenter = [...charts.values()][0].presenter;
  if (!presenter || !presenter.panes || !presenter.panes[0]) return {state: 'no_pane'};
  const axis = presenter.panes[0].axes && presenter.panes[0].axes[0];
  if (!axis || !axis.plots) return {state: 'no_axis'};
"""

# 圖表還沒建好的中間狀態——這些要繼續等，不是錯誤。
TRANSIENT_STATES = {"no_widget", "no_chart", "no_pane", "no_axis", "computing"}

PROBE_JS = """
(() => {
  if (window.bcIsLoggedIn === false) return {state: 'logged_out'};
  %s
  const m = w._panel._model;
  const vp = axis.plots.find(x => /VOLAP/.test(x._title || ''));
  return {
    state: vp ? 'has_volap' : 'no_volap',
    period: m.selectedPeriod && m.selectedPeriod.key,
    aggregation: m.selectedAggregation && m.selectedAggregation.name,
    title: vp ? vp._title : null
  };
})()
""" % _PLOT_JS

# changePeriod 的簽名是 (periodKey, aggregationName)，**兩個字串**。
# 傳整個 period 物件會丟 "Cannot read properties of undefined (reading 'length')"。
SET_PERIOD_JS = """
(() => {
  const w = document.querySelector('interactive-chart-widget');
  if (!w || !w._panel) return {ok: false, error: 'no panel'};
  const m = w._panel._model;
  const target = (m.periods || []).find(x => x.key === '%s');
  if (!target) return {ok: false, error: 'period not found'};
  try { w._panel.changePeriod(target.key, target.aggregation); }
  catch (e) { return {ok: false, error: String(e).slice(0, 200)}; }
  return {ok: true, key: target.key, aggregation: target.aggregation};
})()
"""

READ_JS = """
(() => {
  if (window.bcIsLoggedIn === false) return {state: 'logged_out'};
  %s
  const m = w._panel._model;
  const vp = axis.plots.find(x => /VOLAP/.test(x._title || ''));
  if (!vp) return {state: 'no_volap'};
  const out = {
    period: m.selectedPeriod && m.selectedPeriod.key,
    aggregation: m.selectedAggregation && m.selectedAggregation.name,
    title: vp._title,
    inputs: (vp.timeSeries && vp.timeSeries.inputs) || {}
  };
  const ann = (vp.annotations || [])[0];
  // 重算期間 boxes 是空陣列、gotData 是 false——兩個都要看。
  if (!ann || !ann.gotData || !ann.boxes || !ann.boxes.length) {
    return Object.assign(out, {state: 'computing'});
  }
  if (ann.boxes[0].min == null || ann.boxes[0].max == null) {
    return Object.assign(out, {state: 'computing'});
  }
  const b = ann.boxes[0];
  return Object.assign(out, {
    state: 'ready',
    min: b.min, max: b.max, zone: b.zone, poc_index: b.maxVolumeIndex,
    bars: b.bars.map(x => ({
      up: x.upVolume, down: x.downVolume, is_value: !!x.isValue
    }))
  });
})()
""" % _PLOT_JS


def fail(status, error=None):
    payload = {"status": status}
    if error:
        payload["error"] = str(error)[:300]
    print(json.dumps(payload))


async def poll(ws, target_id, js, ready_states, timeout_s, timeout_status):
    """
    輪詢頁面狀態直到抵達 ready_states 之一。
    回傳 (payload, None) 或 (None, status)。

    暫時性狀態（圖表還在建、VOLAP 還在算）就繼續等，每輪重新 activate——
    分頁一旦被丟到背景，Chrome 會凍結 renderer，VOLAP 永遠不會算完。
    """
    deadline = asyncio.get_event_loop().time() + timeout_s
    while True:
        r = await cdp_eval(ws, js, target_id=target_id)
        # cdp_eval 回 None 代表 JS 求值結果是 null——我們的腳本一律回物件，
        # 所以 None 只可能是頁面被換成登入頁之類的整頁改變。
        if r is None:
            return None, "barchart_session_expired"
        state = r.get("state")
        if state == "logged_out":
            return None, "barchart_session_expired"
        if state == "no_volap":
            return None, "no_volap_plot"
        if state in ready_states:
            return r, None
        if state not in TRANSIENT_STATES:
            return None, "error"
        if asyncio.get_event_loop().time() >= deadline:
            return None, timeout_status
        await activate_target(target_id)
        await asyncio.sleep(POLL_INTERVAL_S)


async def main(symbol):
    target_id, ws = await prepare_page(symbol, TARGET_PATH, settle_ms=8000)
    if not ws:
        fail("error", "No Chrome CDP page found")
        return

    # prepare_page 可能剛剛重新導航過這個分頁（喚醒後第一次 eval 逾時就會觸發），
    # 圖表要好幾秒才建得起來。先等它建好再談切換期間。
    probe, status = await poll(ws, target_id, PROBE_JS, {"has_volap"},
                               CHART_READY_TIMEOUT_S, "chart_not_ready")
    if status:
        fail(status, "圖上沒有掛 VOLAP 指標，請在 Barchart 的 interactive-chart 加入 "
                     "Volume Profile 並存成預設模板" if status == "no_volap_plot" else None)
        return

    original_period = probe.get("period")
    switched = False

    # 已經在目標設定就不要多切一次——切換會觸發重算，白等 5 秒以上。
    if probe.get("period") != TARGET_PERIOD_KEY or probe.get("aggregation") != TARGET_AGGREGATION:
        setr = await cdp_eval(ws, SET_PERIOD_JS % TARGET_PERIOD_KEY, target_id=target_id)
        if not (setr or {}).get("ok"):
            fail("error", "changePeriod failed: %s" % (setr or {}).get("error"))
            return
        switched = True

    data, status = await poll(ws, target_id, READ_JS, {"ready"},
                              POLL_TIMEOUT_S, "volap_timeout")

    # 不管成功失敗都把使用者的圖切回原本的設定——這是他正在看的畫面。
    if switched and original_period:
        try:
            await cdp_eval(ws, SET_PERIOD_JS % original_period, target_id=target_id)
        except Exception:
            pass

    if status:
        fail(status)
        return

    print(json.dumps({
        "status": "success",
        "symbol": symbol,
        "period_key": data.get("period"),
        "aggregation": data.get("aggregation"),
        "title": data.get("title"),
        "inputs": data.get("inputs"),
        "min": data["min"],
        "max": data["max"],
        "zone": data["zone"],
        "poc_index": data["poc_index"],
        "bars": data["bars"],
    }))


if __name__ == "__main__":
    sym = sys.argv[1].upper() if len(sys.argv) > 1 else "SHOP"
    try:
        asyncio.run(main(sym))
    except Exception as e:
        fail("error", e)
