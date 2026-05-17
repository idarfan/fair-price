# BUILD: IV Skew Watchlist 完整建置（FairPrice Rails + pm2）

> 讀取本文件後，依序完成所有步驟，每步驟完成後簡短確認再繼續。
> 涵蓋：Rails Watchlist 管理介面 + Python 抓取腳本 + pm2 排程。

---

## 功能目標

- FairPrice 內新增 `/iv_watchlists` 頁面，可新增/刪除/停用美股追蹤標的
- 清單存入 PostgreSQL `iv_watchlists` 表格
- Python 抓取腳本每日自動從 DB 讀取清單，抓取 IV Skew 並存回 DB
- 以 pm2 取代 cron job 管理排程，支援 log 管理與開機自啟

---

## Step 1：DB Migration

```bash
rails generate migration CreateIvWatchlist
```

編輯產生的 migration 檔：

```ruby
class CreateIvWatchlist < ActiveRecord::Migration[7.1]
  def change
    create_table :iv_watchlists do |t|
      t.string  :symbol,    null: false
      t.string  :group_tag, default: 'general'
      t.boolean :active,    default: true, null: false
      t.timestamps
    end

    add_index :iv_watchlists, :symbol, unique: true
    add_index :iv_watchlists, :group_tag
  end
end
```

```bash
rails db:migrate
```

在 `db/seeds.rb` 末尾加入預設清單：

```ruby
[
  { symbol: 'QQQ',  group_tag: 'index' },
  { symbol: 'SPY',  group_tag: 'index' },
  { symbol: 'IWM',  group_tag: 'index' },
  { symbol: 'SQQQ', group_tag: 'leveraged' },
  { symbol: 'TQQQ', group_tag: 'leveraged' },
  { symbol: 'GLD',  group_tag: 'macro' },
  { symbol: 'TLT',  group_tag: 'macro' },
].each do |attrs|
  IvWatchlist.find_or_create_by(symbol: attrs[:symbol]).update(attrs)
end
```

```bash
rails db:seed
```

---

## Step 2：Model

建立 `app/models/iv_watchlist.rb`：

```ruby
class IvWatchlist < ApplicationRecord
  GROUP_TAGS = %w[general index leveraged macro].freeze

  validates :symbol,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: {
              with: /\A[A-Za-z\-\.]{1,10}\z/,
              message: '只允許英文字母、- 和 .'
            }
  validates :group_tag, inclusion: { in: GROUP_TAGS }

  before_save { self.symbol = symbol.upcase.strip }

  scope :active,   -> { where(active: true) }
  scope :by_group, -> { order(:group_tag, :symbol) }
end
```

---

## Step 3：Controller

建立 `app/controllers/iv_watchlists_controller.rb`：

```ruby
class IvWatchlistsController < ApplicationController
  def index
    @grouped  = IvWatchlist.active.by_group.group_by(&:group_tag)
    @new_item = IvWatchlist.new
    render IvWatchlists::IndexView.new(grouped: @grouped, new_item: @new_item)
  end

  def create
    @item = IvWatchlist.new(watchlist_params)
    if @item.save
      respond_to do |format|
        format.html { redirect_to iv_watchlists_path, notice: "#{@item.symbol} 已加入追蹤清單" }
        format.json { render json: { success: true, item: @item } }
      end
    else
      respond_to do |format|
        format.html { redirect_to iv_watchlists_path, alert: @item.errors.full_messages.join(', ') }
        format.json { render json: { success: false, errors: @item.errors.full_messages }, status: 422 }
      end
    end
  end

  def destroy
    @item  = IvWatchlist.find(params[:id])
    symbol = @item.symbol
    @item.destroy
    respond_to do |format|
      format.html { redirect_to iv_watchlists_path, notice: "#{symbol} 已移除" }
      format.json { render json: { success: true } }
    end
  end

  def toggle
    @item = IvWatchlist.find(params[:id])
    @item.update(active: !@item.active)
    render json: { success: true, active: @item.active }
  end

  private

  def watchlist_params
    params.require(:iv_watchlist).permit(:symbol, :group_tag)
  end
end
```

---

## Step 4：Routes

在 `config/routes.rb` 加入：

```ruby
resources :iv_watchlists, only: [:index, :create, :destroy] do
  member do
    patch :toggle
  end
end
```

---

## Step 5：Phlex 元件

建立 `app/views/iv_watchlists/index_view.rb`：

```ruby
class IvWatchlists::IndexView < ApplicationView
  GROUP_COLORS = {
    'index'     => 'bg-blue-500/10 text-blue-300 border-blue-500/30',
    'leveraged' => 'bg-orange-500/10 text-orange-300 border-orange-500/30',
    'macro'     => 'bg-purple-500/10 text-purple-300 border-purple-500/30',
    'general'   => 'bg-gray-500/10 text-gray-300 border-gray-500/30',
  }.freeze

  def initialize(grouped:, new_item:)
    @grouped  = grouped
    @new_item = new_item
  end

  def view_template
    div(class: 'max-w-3xl mx-auto px-4 py-8') do
      div(class: 'mb-8') do
        h1(class: 'text-2xl font-semibold text-white') { 'IV Skew 追蹤清單' }
        p(class: 'text-gray-400 text-sm mt-1') { '管理每日自動抓取 IV Skew 的美股標的' }
      end

      render AddSymbolForm.new

      if @grouped.empty?
        div(class: 'text-center text-gray-500 py-12') { '清單為空，請先加入標的' }
      else
        div(class: 'space-y-6 mt-8') do
          @grouped.each { |group_tag, items| render GroupSection.new(group_tag:, items:) }
        end
      end
    end
  end

  # ── 新增表單 ────────────────────────────────────────────
  class AddSymbolForm < ApplicationComponent
    QUICK_SYMBOLS = %w[AAPL NVDA TSLA MSFT AMZN META GOOGL AMD].freeze

    def view_template
      div(class: 'bg-gray-900 border border-gray-700 rounded-xl p-6') do
        h2(class: 'text-sm font-medium text-gray-300 mb-4') { '新增標的' }

        form(
          action: '/iv_watchlists',
          method: 'post',
          class: 'flex flex-col sm:flex-row gap-3',
          data: { controller: 'watchlist-form' }
        ) do
          input(type: 'hidden', name: 'authenticity_token',
                value: helpers.form_authenticity_token)

          input(
            type: 'text',
            name: 'iv_watchlist[symbol]',
            placeholder: '美股代號，例如 NVDA',
            maxlength: '10',
            autocomplete: 'off',
            class: 'flex-1 bg-gray-800 border border-gray-600 rounded-lg px-4 py-2
                    text-white placeholder-gray-500 uppercase
                    focus:outline-none focus:border-blue-500 transition-colors',
            data: { watchlist_form_target: 'input' }
          )

          select(
            name: 'iv_watchlist[group_tag]',
            class: 'bg-gray-800 border border-gray-600 rounded-lg px-3 py-2
                    text-gray-300 focus:outline-none focus:border-blue-500 transition-colors'
          ) do
            IvWatchlist::GROUP_TAGS.each { |tag| option(value: tag) { tag.capitalize } }
          end

          button(
            type: 'submit',
            class: 'bg-blue-600 hover:bg-blue-500 text-white font-medium
                    rounded-lg px-5 py-2 transition-colors whitespace-nowrap'
          ) { '+ 加入' }
        end

        div(class: 'mt-4') do
          p(class: 'text-xs text-gray-500 mb-2') { '快速加入：' }
          div(class: 'flex flex-wrap gap-2') do
            QUICK_SYMBOLS.each do |sym|
              button(
                type: 'button',
                class: 'px-3 py-1 text-xs bg-gray-800 hover:bg-gray-700
                        text-gray-300 border border-gray-600 rounded-full
                        transition-colors cursor-pointer',
                data: { symbol: sym, action: 'click->watchlist-form#quickAdd' }
              ) { sym }
            end
          end
        end
      end
    end
  end

  # ── 群組區塊 ────────────────────────────────────────────
  class GroupSection < ApplicationComponent
    def initialize(group_tag:, items:)
      @group_tag = group_tag
      @items     = items
    end

    def view_template
      div(class: 'bg-gray-900 border border-gray-700 rounded-xl overflow-hidden') do
        div(class: 'flex items-center gap-3 px-5 py-3 border-b border-gray-700') do
          span(
            class: "text-xs font-medium px-2 py-0.5 rounded border
                    #{IvWatchlists::IndexView::GROUP_COLORS.fetch(@group_tag,
                        IvWatchlists::IndexView::GROUP_COLORS['general'])}"
          ) { @group_tag.upcase }
          span(class: 'text-gray-400 text-sm') { "#{@items.size} 個標的" }
        end

        div(class: 'divide-y divide-gray-800') do
          @items.each { |item| render SymbolRow.new(item:) }
        end
      end
    end
  end

  # ── 單行標的 ────────────────────────────────────────────
  class SymbolRow < ApplicationComponent
    def initialize(item:)
      @item = item
    end

    def view_template
      div(
        class: 'flex items-center justify-between px-5 py-3
                hover:bg-gray-800/50 transition-colors',
        id: "watchlist-row-#{@item.id}"
      ) do
        div(class: 'flex items-center gap-3') do
          span(class: 'text-white font-mono font-medium text-sm') { @item.symbol }
          span(class: 'text-gray-500 text-xs') {
            "加入於 #{@item.created_at.strftime('%Y/%m/%d')}"
          }
        end

        div(class: 'flex items-center gap-3') do
          # 啟用/停用 toggle
          button(
            type: 'button',
            class: "relative w-9 h-5 rounded-full transition-colors
                    #{@item.active? ? 'bg-green-600' : 'bg-gray-600'}",
            data: {
              action: 'click->watchlist#toggle',
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

          # 刪除
          button(
            type: 'button',
            class: 'text-gray-600 hover:text-red-400 transition-colors px-1',
            data: {
              action:  'click->watchlist#remove',
              url:     "/iv_watchlists/#{@item.id}",
              symbol:  @item.symbol,
              id:      @item.id
            },
            title: "移除 #{@item.symbol}"
          ) { '✕' }
        end
      end
    end
  end
end
```

---

## Step 6：JavaScript（原生事件委派）

先確認專案是否有 Stimulus：

```bash
grep -r "stimulus" package.json 2>/dev/null || echo "no stimulus"
```

### 若有 Stimulus

建立 `app/javascript/controllers/watchlist_controller.js`：

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async toggle(event) {
    const btn = event.currentTarget
    const res = await fetch(btn.dataset.url, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'application/json',
      }
    })
    const data = await res.json()
    if (!data.success) return
    btn.classList.toggle('bg-green-600', data.active)
    btn.classList.toggle('bg-gray-600', !data.active)
    const dot = btn.querySelector('span')
    dot.classList.toggle('left-5', data.active)
    dot.classList.toggle('left-1', !data.active)
  }

  async remove(event) {
    const btn = event.currentTarget
    if (!confirm(`確定移除 ${btn.dataset.symbol}？`)) return
    const res = await fetch(btn.dataset.url, {
      method: 'DELETE',
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Accept': 'application/json',
      }
    })
    const data = await res.json()
    if (data.success) {
      document.getElementById(`watchlist-row-${btn.dataset.id}`)?.remove()
    }
  }
}
```

建立 `app/javascript/controllers/watchlist_form_controller.js`：

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  quickAdd(event) {
    this.inputTarget.value = event.currentTarget.dataset.symbol
    this.inputTarget.focus()
  }
}
```

### 若無 Stimulus

建立 `app/javascript/watchlist.js` 並在 `application.js` 引入：

```javascript
const csrf = () =>
  document.querySelector('meta[name="csrf-token"]')?.content

document.addEventListener('click', async (e) => {
  // Toggle
  const toggleBtn = e.target.closest('[data-action="click->watchlist#toggle"]')
  if (toggleBtn) {
    const res = await fetch(toggleBtn.dataset.url, {
      method: 'PATCH',
      headers: { 'X-CSRF-Token': csrf(), 'Accept': 'application/json' }
    })
    const data = await res.json()
    if (!data.success) return
    toggleBtn.classList.toggle('bg-green-600', data.active)
    toggleBtn.classList.toggle('bg-gray-600', !data.active)
    const dot = toggleBtn.querySelector('span')
    dot.classList.toggle('left-5', data.active)
    dot.classList.toggle('left-1', !data.active)
  }

  // Remove
  const removeBtn = e.target.closest('[data-action="click->watchlist#remove"]')
  if (removeBtn) {
    if (!confirm(`確定移除 ${removeBtn.dataset.symbol}？`)) return
    const res = await fetch(removeBtn.dataset.url, {
      method: 'DELETE',
      headers: { 'X-CSRF-Token': csrf(), 'Accept': 'application/json' }
    })
    const data = await res.json()
    if (data.success) {
      document.getElementById(`watchlist-row-${removeBtn.dataset.id}`)?.remove()
    }
  }

  // Quick add chip
  const chip = e.target.closest('[data-action="click->watchlist-form#quickAdd"]')
  if (chip) {
    const input = document.querySelector('[data-watchlist-form-target="input"]')
    if (input) { input.value = chip.dataset.symbol; input.focus() }
  }
})
```

---

## Step 7：Navigation 連結

找到 FairPrice 的導覽列 Phlex 元件，加入連結：

```ruby
a(href: '/iv_watchlists', class: nav_link_class) { 'IV Watchlist' }
```

---

## Step 8：更新 Python 腳本

更新 `~/.claude/skills/user/iv-skew-tracker/qqq_iv_tracker.py`。

在現有的 `load_watchlist()` 函式**之後**新增：

```python
def load_watchlist_from_db():
    """從 PostgreSQL iv_watchlists 表格讀取啟用中的追蹤清單"""
    sql = """
        SELECT symbol, group_tag
        FROM iv_watchlists
        WHERE active = true
        ORDER BY group_tag, symbol
    """
    try:
        with psycopg2.connect(DB_URL) as conn:
            df = pd.read_sql(sql, conn)
        symbols = df['symbol'].tolist()
        groups  = df.groupby('group_tag')['symbol'].apply(list).to_dict()
        print(f"[DB] 載入 {len(symbols)} 個追蹤標的：{symbols}")
        return {'watchlist': symbols, 'groups': groups}
    except Exception as e:
        print(f"[WARN] 無法從 DB 讀取清單，fallback 到 symbols.json：{e}")
        return load_watchlist()
```

在 `main()` 的 `--all` 分支，將 `load_watchlist()` 改為 `load_watchlist_from_db()`：

```python
if args.all:
    data     = load_watchlist_from_db()   # ← 改這行
    watchlist = data['watchlist']
    ...
```

---

## Step 9：安裝 pm2 並設定排程

### 9-1 安裝 pm2

```bash
npm install -g pm2
pm2 --version   # 確認安裝成功
```

### 9-2 建立 ecosystem 設定檔

建立 `~/.claude/skills/user/iv-skew-tracker/ecosystem.config.js`：

```javascript
module.exports = {
  apps: [{
    name:         'iv-skew',
    script:       'qqq_iv_tracker.py',
    interpreter:  'python3',
    cwd:          '/home/idarfan/.claude/skills/user/iv-skew-tracker',
    args:         '--all',
    cron_restart: '30 4 * * 1-5',  // 台灣時間 04:30，週一到週五
    autorestart:  false,            // cron 模式下執行完即結束，不重啟
    watch:        false,
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    out_file:     '/home/idarfan/.claude/skills/user/iv-skew-tracker/logs/pm2-out.log',
    error_file:   '/home/idarfan/.claude/skills/user/iv-skew-tracker/logs/pm2-err.log',
    merge_logs:   true,
  }]
}
```

### 9-3 啟動並設定開機自啟

```bash
mkdir -p ~/.claude/skills/user/iv-skew-tracker/logs

cd ~/.claude/skills/user/iv-skew-tracker
pm2 start ecosystem.config.js

# 儲存目前 pm2 process 清單
pm2 save

# 產生開機自啟指令（複製輸出的那行 sudo 指令並執行）
pm2 startup
```

### 9-4 移除舊的 crontab（若有）

```bash
crontab -e
# 找到並刪除含有 iv-skew-tracker 或 qqq_iv_tracker 的那行
```

### 9-5 驗證 pm2 設定

```bash
pm2 list                         # 確認 iv-skew 出現，status 為 online 或 stopped
pm2 logs iv-skew --lines 20      # 查看最近 log
pm2 restart iv-skew              # 手動觸發一次抓取（測試用）
```

---

## Step 10：最終驗證

```bash
# Rails 端
rails db:migrate
rails db:seed
rails server

# 瀏覽 http://localhost:3000/iv_watchlists
# 確認：
# 1. 7 個預設標的正常顯示
# 2. 輸入 NVDA 按加入 → 清單更新
# 3. 點快速加入 chip → 自動填入輸入框
# 4. Toggle 切換啟用狀態
# 5. ✕ 刪除標的

# Python 端
cd ~/.claude/skills/user/iv-skew-tracker
python3 qqq_iv_tracker.py --all
# 確認 log 印出「從資料庫載入 N 個追蹤標的」

# pm2 端
pm2 list
# 確認 iv-skew 在清單中
```

---

## 完成後回報

1. `rails db:migrate` 輸出
2. `/iv_watchlists` 頁面是否正常顯示
3. 新增一個標的後 `SELECT symbol, group_tag, active FROM iv_watchlists;` 結果
4. `python3 qqq_iv_tracker.py --all` 的 log 輸出
5. `pm2 list` 輸出截圖
