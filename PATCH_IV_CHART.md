# PATCH: IV Skew 圖表功能（點擊標的展開 Chart.js）

> 這是在 BUILD_IV_SKEW_COMPLETE.md 完成後執行的補丁。
> 新增：點擊標的 → 展開 Chart.js 圖表（Put IV / Call IV / Skew）
> 資料來源：Rails JSON API 讀取 qqq_iv_daily

---

## Step 1：新增 JSON API endpoint

在 `iv_watchlists_controller.rb` 新增 `chart_data` action：

```ruby
def chart_data
  symbol = params[:symbol].upcase
  days   = (params[:days] || 90).to_i

  rows = ActiveRecord::Base.connection.execute(<<~SQL)
    SELECT
      to_char(date, 'YYYY-MM-DD') AS date,
      ROUND(put_iv_30d  * 100, 2)  AS put_iv,
      ROUND(call_iv_30d * 100, 2)  AS call_iv,
      ROUND(skew        * 100, 2)  AS skew,
      stock_price
    FROM qqq_iv_daily
    WHERE symbol = '#{ActiveRecord::Base.sanitize_sql(symbol)}'
      AND date >= CURRENT_DATE - INTERVAL '#{days.to_i} days'
    ORDER BY date ASC
  SQL

  if rows.ntuples.zero?
    render json: { error: 'no_data', symbol: symbol }
    return
  end

  # 計算 75 百分位（用於前端標記恐慌區）
  skews  = rows.map { |r| r['skew'].to_f }
  sorted = skews.sort
  p75_idx = (sorted.size * 0.75).ceil - 1
  p75    = sorted[p75_idx].round(2)

  render json: {
    symbol:     symbol,
    p75:        p75,
    labels:     rows.map { |r| r['date'] },
    put_iv:     rows.map { |r| r['put_iv'].to_f },
    call_iv:    rows.map { |r| r['call_iv'].to_f },
    skew:       rows.map { |r| r['skew'].to_f },
    price:      rows.map { |r| r['stock_price'].to_f },
  }
end
```

---

## Step 2：更新 Routes

```ruby
resources :iv_watchlists, only: [:index, :create, :destroy] do
  member do
    patch :toggle
  end
  collection do
    get 'chart_data/:symbol', to: 'iv_watchlists#chart_data', as: :chart_data
  end
end
```

---

## Step 3：更新 Phlex SymbolRow，加入展開區塊

將 `app/views/iv_watchlists/index_view.rb` 的 `SymbolRow` 類別完整替換：

```ruby
class SymbolRow < ApplicationComponent
  def initialize(item:)
    @item = item
  end

  def view_template
    # 外層 wrapper，包含列與圖表區塊
    div(id: "watchlist-row-#{@item.id}", class: 'border-b border-gray-800 last:border-0') do

      # 標的列（可點擊）
      div(
        class: 'flex items-center justify-between px-5 py-3
                hover:bg-gray-800/50 transition-colors cursor-pointer select-none',
        data: {
          action:  'click->iv-chart#toggle',
          symbol:  @item.symbol,
          row_id:  @item.id,
        }
      ) do
        # 左側
        div(class: 'flex items-center gap-3') do
          # 展開箭頭
          span(
            class: 'text-gray-500 text-xs transition-transform duration-200',
            data: { iv_chart_target: "arrow-#{@item.id}" }
          ) { '▶' }
          span(class: 'text-white font-mono font-medium text-sm') { @item.symbol }
          span(class: 'text-gray-500 text-xs') {
            "加入於 #{@item.created_at.strftime('%Y/%m/%d')}"
          }
        end

        # 右側：toggle + 刪除
        div(class: 'flex items-center gap-3') do
          button(
            type: 'button',
            class: "relative w-9 h-5 rounded-full transition-colors
                    #{@item.active? ? 'bg-green-600' : 'bg-gray-600'}",
            data: {
              action: 'click->watchlist#toggle:stop',
              url:    "/iv_watchlists/#{@item.id}/toggle",
              id:     @item.id
            },
            title: @item.active? ? '點擊停用' : '點擊啟用'
          ) do
            span(
              class: "absolute top-1 w-3 h-3 bg-white rounded-full transition-all
                      #{@item.active? ? 'left-5' : 'left-1'}"
            )
          end

          button(
            type: 'button',
            class: 'text-gray-600 hover:text-red-400 transition-colors px-1',
            data: {
              action:  'click->watchlist#remove:stop',
              url:     "/iv_watchlists/#{@item.id}",
              symbol:  @item.symbol,
              id:      @item.id
            },
            title: "移除 #{@item.symbol}"
          ) { '✕' }
        end
      end

      # 圖表展開區塊（預設隱藏）
      div(
        id: "chart-panel-#{@item.id}",
        class: 'hidden px-5 pb-5 pt-2',
        data: { iv_chart_target: "panel-#{@item.id}" }
      ) do
        # 天數選擇
        div(class: 'flex gap-2 mb-3') do
          [30, 60, 90, 180].each do |d|
            button(
              type: 'button',
              class: "px-3 py-1 text-xs rounded border transition-colors
                      #{d == 90 ? 'bg-blue-600 border-blue-500 text-white'
                                : 'bg-gray-800 border-gray-600 text-gray-400 hover:text-white'}",
              data: {
                action: 'click->iv-chart#changeDays',
                symbol: @item.symbol,
                days:   d,
                row_id: @item.id,
              }
            ) { "#{d}天" }
          end
        end

        # 載入中提示
        div(
          class: 'text-gray-500 text-sm text-center py-4',
          data: { iv_chart_target: "loading-#{@item.id}" }
        ) { '載入中...' }

        # Canvas 容器
        div(class: 'relative', style: 'height: 280px') do
          canvas(
            id: "chart-iv-#{@item.id}",
            data: { iv_chart_target: "canvas-#{@item.id}" }
          )
        end

        div(class: 'relative mt-3', style: 'height: 120px') do
          canvas(
            id: "chart-skew-#{@item.id}",
            data: { iv_chart_target: "skew-canvas-#{@item.id}" }
          )
        end

        # 圖例說明
        div(class: 'flex gap-4 mt-2 text-xs text-gray-500') do
          span { '🔴 Put IV' }
          span { '🟢 Call IV' }
          span { '⬛ 股價（右軸）' }
          span { '🟣 Skew 超過 75th pct = 恐慌區' }
        end
      end
    end
  end
end
```

---

## Step 4：引入 Chart.js CDN

在 FairPrice 的 layout 檔案（通常是 `app/views/layouts/application.html.erb`
或對應的 Phlex layout 元件）的 `</head>` 前加入：

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
```

---

## Step 5：建立 iv_chart JavaScript controller

### 若有 Stimulus

建立 `app/javascript/controllers/iv_chart_controller.js`：

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // 存放每個 symbol 的 Chart 實例
  charts = {}

  async toggle(event) {
    const { symbol, rowId } = event.currentTarget.dataset
    const panel  = document.getElementById(`chart-panel-${rowId}`)
    const arrow  = this.element.querySelector(`[data-iv-chart-target="arrow-${rowId}"]`)
    const isOpen = !panel.classList.contains('hidden')

    if (isOpen) {
      panel.classList.add('hidden')
      arrow.style.transform = ''
      return
    }

    panel.classList.remove('hidden')
    arrow.style.transform = 'rotate(90deg)'
    await this.loadChart(symbol, rowId, 90)
  }

  async changeDays(event) {
    const { symbol, days, rowId } = event.currentTarget.dataset

    // 更新按鈕樣式
    const panel = document.getElementById(`chart-panel-${rowId}`)
    panel.querySelectorAll('[data-action*="changeDays"]').forEach(btn => {
      btn.classList.remove('bg-blue-600', 'border-blue-500', 'text-white')
      btn.classList.add('bg-gray-800', 'border-gray-600', 'text-gray-400')
    })
    event.currentTarget.classList.add('bg-blue-600', 'border-blue-500', 'text-white')
    event.currentTarget.classList.remove('bg-gray-800', 'border-gray-600', 'text-gray-400')

    await this.loadChart(symbol, rowId, parseInt(days))
  }

  async loadChart(symbol, rowId, days) {
    const loadingEl = this.element.querySelector(`[data-iv-chart-target="loading-${rowId}"]`)
    if (loadingEl) loadingEl.classList.remove('hidden')

    // 銷毀舊 chart
    if (this.charts[`${rowId}-iv`])   this.charts[`${rowId}-iv`].destroy()
    if (this.charts[`${rowId}-skew`]) this.charts[`${rowId}-skew`].destroy()

    const res  = await fetch(`/iv_watchlists/chart_data/${symbol}?days=${days}`)
    const data = await res.json()

    if (loadingEl) loadingEl.classList.add('hidden')

    if (data.error === 'no_data') {
      const canvas = document.getElementById(`chart-iv-${rowId}`)
      const ctx = canvas.getContext('2d')
      ctx.fillStyle = '#666'
      ctx.font = '14px sans-serif'
      ctx.textAlign = 'center'
      ctx.fillText('尚無資料，請等待每日抓取累積', canvas.width / 2, 60)
      return
    }

    this.drawIvChart(data, rowId)
    this.drawSkewChart(data, rowId)
  }

  drawIvChart(data, rowId) {
    const canvas = document.getElementById(`chart-iv-${rowId}`)
    const ctx    = canvas.getContext('2d')

    this.charts[`${rowId}-iv`] = new Chart(ctx, {
      type: 'line',
      data: {
        labels: data.labels,
        datasets: [
          {
            label:       'Put IV %',
            data:        data.put_iv,
            borderColor: '#E85D5D',
            borderWidth: 1.5,
            pointRadius: 0,
            tension:     0.3,
            yAxisID:     'y',
          },
          {
            label:       'Call IV %',
            data:        data.call_iv,
            borderColor: '#2ECC9A',
            borderWidth: 1.5,
            pointRadius: 0,
            tension:     0.3,
            yAxisID:     'y',
          },
          {
            label:           '股價',
            data:            data.price,
            borderColor:     '#D4A017',
            borderWidth:     1.2,
            borderDash:      [4, 3],
            pointRadius:     0,
            tension:         0.3,
            yAxisID:         'y2',
          },
        ]
      },
      options: {
        responsive:          true,
        maintainAspectRatio: false,
        interaction:         { mode: 'index', intersect: false },
        plugins: {
          legend: {
            labels: { color: '#aaaaaa', font: { size: 10 } }
          },
          tooltip: {
            backgroundColor: '#1a1a1a',
            titleColor:      '#cccccc',
            bodyColor:       '#aaaaaa',
          }
        },
        scales: {
          x: {
            ticks: { color: '#666', maxTicksLimit: 8, font: { size: 9 } },
            grid:  { color: '#1e1e1e' },
          },
          y: {
            position: 'left',
            ticks:    { color: '#aaaaaa', font: { size: 9 } },
            grid:     { color: '#1e1e1e' },
            title:    { display: true, text: 'IV %', color: '#aaaaaa', font: { size: 9 } },
          },
          y2: {
            position: 'right',
            ticks:    { color: '#D4A017', font: { size: 9 } },
            grid:     { drawOnChartArea: false },
            title:    { display: true, text: 'Price', color: '#D4A017', font: { size: 9 } },
          },
        }
      }
    })
  }

  drawSkewChart(data, rowId) {
    const canvas = document.getElementById(`chart-skew-${rowId}`)
    const ctx    = canvas.getContext('2d')
    const p75    = data.p75

    // 柱子顏色：超過 75th pct 用桃紅色
    const barColors = data.skew.map(v =>
      v >= p75 ? 'rgba(224, 64, 176, 0.75)' : 'rgba(85, 119, 170, 0.75)'
    )

    this.charts[`${rowId}-skew`] = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: data.labels,
        datasets: [{
          label:           'Skew (Put−Call) %',
          data:            data.skew,
          backgroundColor: barColors,
          borderWidth:     0,
        }]
      },
      options: {
        responsive:          true,
        maintainAspectRatio: false,
        plugins: {
          legend: { labels: { color: '#aaaaaa', font: { size: 10 } } },
          tooltip: {
            backgroundColor: '#1a1a1a',
            titleColor:      '#cccccc',
            bodyColor:       '#aaaaaa',
            callbacks: {
              afterBody: (items) => {
                const v = items[0]?.raw
                return v >= p75 ? ['⚠️ 恐慌區（> 75th pct）'] : []
              }
            }
          },
          // 75th pct 參考線
          annotation: false,
        },
        scales: {
          x: {
            ticks: { color: '#666', maxTicksLimit: 8, font: { size: 9 } },
            grid:  { color: '#1e1e1e' },
          },
          y: {
            ticks: { color: '#aaaaaa', font: { size: 9 } },
            grid:  { color: '#1e1e1e' },
            title: { display: true, text: 'Skew %', color: '#aaaaaa', font: { size: 9 } },
          },
        }
      }
    })
  }
}
```

### 若無 Stimulus，改用原生 JS

建立 `app/javascript/iv_chart.js` 並在 `application.js` 引入：

```javascript
// 存放 Chart 實例
const ivCharts = {}

async function loadIvChart(symbol, rowId, days) {
  const loadingEl = document.querySelector(`[data-iv-chart-target="loading-${rowId}"]`)
  if (loadingEl) loadingEl.classList.remove('hidden')

  if (ivCharts[`${rowId}-iv`])   ivCharts[`${rowId}-iv`].destroy()
  if (ivCharts[`${rowId}-skew`]) ivCharts[`${rowId}-skew`].destroy()

  const res  = await fetch(`/iv_watchlists/chart_data/${symbol}?days=${days}`)
  const data = await res.json()

  if (loadingEl) loadingEl.classList.add('hidden')

  if (data.error === 'no_data') {
    const canvas = document.getElementById(`chart-iv-${rowId}`)
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    ctx.fillStyle = '#666'
    ctx.font = '14px sans-serif'
    ctx.textAlign = 'center'
    ctx.fillText('尚無資料，請等待每日抓取累積', canvas.width / 2, 60)
    return
  }

  // IV 圖
  const ivCanvas = document.getElementById(`chart-iv-${rowId}`)
  if (ivCanvas) {
    ivCharts[`${rowId}-iv`] = new Chart(ivCanvas.getContext('2d'), {
      type: 'line',
      data: {
        labels: data.labels,
        datasets: [
          {
            label: 'Put IV %', data: data.put_iv,
            borderColor: '#E85D5D', borderWidth: 1.5,
            pointRadius: 0, tension: 0.3, yAxisID: 'y',
          },
          {
            label: 'Call IV %', data: data.call_iv,
            borderColor: '#2ECC9A', borderWidth: 1.5,
            pointRadius: 0, tension: 0.3, yAxisID: 'y',
          },
          {
            label: '股價', data: data.price,
            borderColor: '#D4A017', borderWidth: 1.2,
            borderDash: [4,3], pointRadius: 0, tension: 0.3, yAxisID: 'y2',
          },
        ]
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { labels: { color: '#aaaaaa', font: { size: 10 } } },
          tooltip: { backgroundColor: '#1a1a1a', titleColor: '#cccccc', bodyColor: '#aaaaaa' },
        },
        scales: {
          x: { ticks: { color: '#666', maxTicksLimit: 8, font: { size: 9 } }, grid: { color: '#1e1e1e' } },
          y: { position: 'left', ticks: { color: '#aaaaaa', font: { size: 9 } }, grid: { color: '#1e1e1e' },
               title: { display: true, text: 'IV %', color: '#aaaaaa', font: { size: 9 } } },
          y2: { position: 'right', ticks: { color: '#D4A017', font: { size: 9 } },
                grid: { drawOnChartArea: false },
                title: { display: true, text: 'Price', color: '#D4A017', font: { size: 9 } } },
        }
      }
    })
  }

  // Skew 圖
  const skewCanvas = document.getElementById(`chart-skew-${rowId}`)
  if (skewCanvas) {
    const barColors = data.skew.map(v =>
      v >= data.p75 ? 'rgba(224,64,176,0.75)' : 'rgba(85,119,170,0.75)'
    )
    ivCharts[`${rowId}-skew`] = new Chart(skewCanvas.getContext('2d'), {
      type: 'bar',
      data: {
        labels: data.labels,
        datasets: [{ label: 'Skew %', data: data.skew, backgroundColor: barColors, borderWidth: 0 }]
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: {
          legend: { labels: { color: '#aaaaaa', font: { size: 10 } } },
          tooltip: {
            backgroundColor: '#1a1a1a', titleColor: '#cccccc', bodyColor: '#aaaaaa',
            callbacks: {
              afterBody: (items) => items[0]?.raw >= data.p75 ? ['⚠️ 恐慌區'] : []
            }
          },
        },
        scales: {
          x: { ticks: { color: '#666', maxTicksLimit: 8, font: { size: 9 } }, grid: { color: '#1e1e1e' } },
          y: { ticks: { color: '#aaaaaa', font: { size: 9 } }, grid: { color: '#1e1e1e' },
               title: { display: true, text: 'Skew %', color: '#aaaaaa', font: { size: 9 } } },
        }
      }
    })
  }
}

// 事件委派
document.addEventListener('click', async (e) => {
  // 點擊標的列 → 展開/收合
  const row = e.target.closest('[data-action*="iv-chart#toggle"]')
  if (row && !e.target.closest('[data-action*="toggle"]') && !e.target.closest('[data-action*="remove"]')) {
    const { symbol, rowId } = row.dataset
    const panel = document.getElementById(`chart-panel-${rowId}`)
    const arrow = document.querySelector(`[data-iv-chart-target="arrow-${rowId}"]`)
    const isOpen = !panel.classList.contains('hidden')

    if (isOpen) {
      panel.classList.add('hidden')
      if (arrow) arrow.style.transform = ''
    } else {
      panel.classList.remove('hidden')
      if (arrow) arrow.style.transform = 'rotate(90deg)'
      await loadIvChart(symbol, rowId, 90)
    }
  }

  // 點擊天數按鈕
  const dayBtn = e.target.closest('[data-action*="changeDays"]')
  if (dayBtn) {
    const { symbol, days, rowId } = dayBtn.dataset
    const panel = document.getElementById(`chart-panel-${rowId}`)
    panel.querySelectorAll('[data-action*="changeDays"]').forEach(btn => {
      btn.classList.remove('bg-blue-600', 'border-blue-500', 'text-white')
      btn.classList.add('bg-gray-800', 'border-gray-600', 'text-gray-400')
    })
    dayBtn.classList.add('bg-blue-600', 'border-blue-500', 'text-white')
    dayBtn.classList.remove('bg-gray-800', 'border-gray-600', 'text-gray-400')
    await loadIvChart(symbol, rowId, parseInt(days))
  }
})
```

---

## Step 6：驗證

```bash
rails server
```

1. 開啟 `http://localhost:3000/iv_watchlists`
2. 點擊任一標的列 → 圖表區展開，出現「載入中...」
3. 若 DB 已有資料 → 顯示 Put IV（紅）/ Call IV（綠）/ 股價（黃虛線）+ Skew 柱狀圖
4. 若 DB 無資料 → 顯示「尚無資料，請等待每日抓取累積」
5. 點擊 30 / 60 / 90 / 180 天按鈕 → 圖表更新
6. 再次點擊標的列 → 圖表收合

---

## 完成後回報

- 點擊標的後的頁面截圖
- `GET /iv_watchlists/chart_data/QQQ` 的 JSON 回應內容
