# 持股結構頁面改版方案

## 目標

將持股結構頁面從「單一快照」改為「趨勢追蹤」，讓使用者能觀察機構與內部人持股的歷史變化。

---

## 一、資料層：累積歷史快照（PostgreSQL）

### Model 設計

兩張表：`ownership_snapshots`（總覽）和 `ownership_holders`（個別機構）。

#### Migration

```ruby
# db/migrate/xxx_create_ownership_snapshots.rb
class CreateOwnershipSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :ownership_snapshots do |t|
      t.string  :ticker,             null: false
      t.string  :quarter,            null: false  # "2025-Q4"
      t.date    :snapshot_date,      null: false
      t.decimal :institutional_pct,  precision: 6, scale: 2
      t.decimal :insider_pct,        precision: 6, scale: 2
      t.integer :institution_count
      t.timestamps
    end

    add_index :ownership_snapshots, [:ticker, :quarter], unique: true
    add_index :ownership_snapshots, [:ticker, :snapshot_date]
  end
end

# db/migrate/xxx_create_ownership_holders.rb
class CreateOwnershipHolders < ActiveRecord::Migration[8.0]
  def change
    create_table :ownership_holders do |t|
      t.references :ownership_snapshot, null: false, foreign_key: true
      t.string  :name,        null: false
      t.decimal :pct,         precision: 8, scale: 4
      t.bigint  :market_value
      t.date    :filing_date
      t.timestamps
    end

    add_index :ownership_holders, [:ownership_snapshot_id, :name], unique: true
  end
end
```

#### Model

```ruby
# app/models/ownership_snapshot.rb
class OwnershipSnapshot < ApplicationRecord
  has_many :ownership_holders, dependent: :destroy

  validates :ticker, :quarter, :snapshot_date, presence: true
  validates :quarter, uniqueness: { scope: :ticker }

  scope :for_ticker, ->(ticker) { where(ticker: ticker).order(:snapshot_date) }
  scope :latest, ->(ticker) { for_ticker(ticker).last }
end

# app/models/ownership_holder.rb
class OwnershipHolder < ApplicationRecord
  belongs_to :ownership_snapshot

  validates :name, presence: true
  validates :name, uniqueness: { scope: :ownership_snapshot_id }
end
```

### 抓取邏輯

- 使用者點「抓取快照」時，呼叫 Yahoo Finance API 取得最新 ownership 資料
- 用 `ticker` + `quarter` 查詢是否已有快照
  - 有 → 更新該筆（update attributes + replace holders）
  - 沒有 → 建立新的 snapshot + holders
- 用 transaction 包住確保一致性

### Service 建議

```ruby
# app/services/ownership_snapshot_service.rb
class OwnershipSnapshotService
  def save_snapshot(ticker, data)
    ActiveRecord::Base.transaction do
      snapshot = OwnershipSnapshot.find_or_initialize_by(
        ticker: ticker,
        quarter: current_quarter
      )
      snapshot.update!(
        snapshot_date: Date.current,
        institutional_pct: data[:institutional_pct],
        insider_pct: data[:insider_pct],
        institution_count: data[:institution_count]
      )
      snapshot.ownership_holders.destroy_all
      data[:top_holders].each do |holder|
        snapshot.ownership_holders.create!(holder)
      end
      snapshot
    end
  end

  def load_history(ticker)
    OwnershipSnapshot.for_ticker(ticker).includes(:ownership_holders)
  end

  def previous_snapshot(ticker)
    snapshots = OwnershipSnapshot.for_ticker(ticker).last(2)
    snapshots.length == 2 ? snapshots.first : nil
  end

  def current_quarter
    q = (Date.current.month - 1) / 3 + 1
    "#{Date.current.year}-Q#{q}"
  end
end
```

---

## 二、前端架構：Vite + React + Recharts

持股結構頁面**不使用 Phlex**，改用 Vite + React 獨立建構。

### 技術棧

- **Vite**：前端打包
- **React**：UI 元件
- **Recharts**：圖表（`AreaChart` + `LineChart`）
- **Tailwind CSS**：樣式（沿用專案既有設定）

### API 端點

Rails 提供 JSON API，React 前端透過 fetch 取資料：

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :ownership_snapshots, only: [:index, :create], param: :ticker
  end
end

# GET  /api/v1/ownership_snapshots/:ticker?range=90d|1q|6m|1y → 歷史快照（依時間範圍過濾）
# POST /api/v1/ownership_snapshots/:ticker → 抓取新快照
```

```ruby
# app/controllers/api/v1/ownership_snapshots_controller.rb
class Api::V1::OwnershipSnapshotsController < ApplicationController
  def index
    snapshots = OwnershipSnapshot.for_ticker(params[:ticker])
                                 .where("snapshot_date >= ?", range_start)
                                 .includes(:ownership_holders)
    render json: {
      snapshots: snapshots.map { |s| serialize_snapshot(s) },
      previous: serialize_snapshot(service.previous_snapshot(params[:ticker]))
    }
  end

  def create
    snapshot = service.save_snapshot(params[:ticker], fetched_data)
    render json: { snapshot: serialize_snapshot(snapshot) }
  end

  private

  def service = OwnershipSnapshotService.new

  # GET /api/v1/ownership_snapshots/WULF?range=90d
  # 支援：90d / 1q / 6m / 1y
  def range_start
    case params[:range]
    when "90d" then 90.days.ago.to_date
    when "1q"  then 3.months.ago.to_date
    when "6m"  then 6.months.ago.to_date
    when "1y"  then 1.year.ago.to_date
    else            1.year.ago.to_date  # 預設 1 年
    end
  end

  def serialize_snapshot(snapshot)
    return nil unless snapshot
    {
      quarter: snapshot.quarter,
      date: snapshot.snapshot_date,
      institutional_pct: snapshot.institutional_pct.to_f,
      insider_pct: snapshot.insider_pct.to_f,
      institution_count: snapshot.institution_count,
      holders: snapshot.ownership_holders.map { |h|
        { name: h.name, pct: h.pct.to_f, value: h.market_value, filing_date: h.filing_date }
      }
    }
  end
end
```

### React 元件結構

```
app/javascript/
├── ownership/
│   ├── App.jsx                      # 進入點，fetch 資料 + 狀態管理
│   ├── components/
│   │   ├── MetricCards.jsx          # 三張 metric cards
│   │   ├── TimeRangeSelector.jsx    # 時間範圍切換器
│   │   ├── OwnershipTrendChart.jsx  # Recharts 折線圖
│   │   └── HoldersTable.jsx         # 機構持有人表格
│   └── utils/
│       └── format.js                # 數值格式化 helpers
```

### 2-1. MetricCards.jsx

三張卡片，每張顯示「vs 上季變化」：

```
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ 機構持股         │ │ 內部人持股       │ │ 機構數量         │
│ 42.3%           │ │ 8.7%            │ │ 156             │
│ +3.1% vs 上季   │ │ -1.2% vs 上季   │ │ +12 vs 上季     │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

- 變化為正 → 綠色文字（`text-green-400`）
- 變化為負 → 紅色文字（`text-red-400`）
- 只有一筆快照時 → 不顯示變化，顯示「—」

### 2-2. TimeRangeSelector.jsx

趨勢圖上方的時間範圍切換器，四個按鈕：

```
[ 90天 ] [ 季度 ] [ 半年 ] [ 1年 ]
```

```jsx
const RANGES = [
  { key: '90d', label: '90天' },
  { key: '1q',  label: '季度' },
  { key: '6m',  label: '半年' },
  { key: '1y',  label: '1年' },
];

// 選中的按鈕用 active 樣式（例如 bg-blue-600 text-white）
// 切換時觸發 onRangeChange(key) → App.jsx refetch API with ?range=key
```

- 預設選中「1年」
- 切換時重新呼叫 `GET /api/v1/ownership_snapshots/:ticker?range=90d`
- Metric Cards 的「vs 上季」也跟著更新（比較範圍內最後兩筆）
- 圖表和表格同步更新

### 2-3. OwnershipTrendChart.jsx（Recharts）

**圖表類型：** `ComposedChart` with `Area`

```jsx
import { ComposedChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

// data 根據目前選擇的 range 從 API 回傳的 snapshots 轉換：
// snapshots.map(s => ({
//   quarter: s.quarter,      // range=90d 時 X 軸用 date 而非 quarter
//   label: s.date,           // tooltip 顯示完整日期
//   institutional: s.institutional_pct,
//   insider: s.insider_pct,
// }))

<ResponsiveContainer width="100%" height={280}>
  <ComposedChart data={data}>
    <XAxis dataKey="quarter" />
    <YAxis tickFormatter={(v) => `${v}%`} />
    <Tooltip content={<CustomTooltip />} />
    <Area dataKey="institutional" fill="rgba(55,138,221,0.08)" stroke="#378ADD" name="機構持股" />
    <Area dataKey="insider" fill="rgba(239,159,39,0.08)" stroke="#EF9F27" name="內部人持股" />
  </ComposedChart>
</ResponsiveContainer>
```

- **X 軸標籤**：range 為 `90d` 時用日期（`03/01`），其餘用季度（`2025-Q4`）
- hover tooltip 顯示：數值 + 跟前一筆的差值（用 custom tooltip component）
- **Fallback**：只有 1 筆 → 顯示文字「目前僅有一筆快照，累積更多資料後將顯示趨勢圖」
- 圖例用自建 HTML，不用 Recharts 預設

### 2-4. HoldersTable.jsx

新增「季度變化」欄位：

| 機構名稱 | 持股% | 季度變化 | 市值 | 申報日 |
|---------|------|---------|-----|-------|
| Vanguard Group Inc | 9.82% | +0.34% | $494M | 2025-12-31 |
| BlackRock Inc | 7.15% | +1.22% | $409M | 2025-12-31 |
| ARK Investment | 2.56% | -2.13% | $152M | 2025-12-31 |

- 季度變化 = 本季持股% - 上季持股%（前端計算，比對同名機構）
- 正值 → 綠色，負值 → 紅色
- 找不到上季資料（新進機構）→ 顯示「NEW」badge
- 上季有但本季消失的機構 → 表格末尾顯示「已退出」

---

## 三、實作順序

### Phase 1：資料層
1. 建立 migration：`ownership_snapshots` + `ownership_holders`
2. 建立 Model：`OwnershipSnapshot`、`OwnershipHolder`（含 validations、scopes、associations）
3. 實作 `OwnershipSnapshotService`（save / load_history / previous_snapshot / current_quarter）
4. 修改現有「抓取快照」按鈕的 controller action，改用 service 儲存到 DB
5. 寫測試：確認 upsert、關聯、排序邏輯正確

### Phase 2：前端基礎建設
1. 專案加入 Vite + React（如果尚未設定）
2. 安裝 `recharts`
3. 建立 `app/javascript/ownership/` 目錄結構
4. 建立 JSON API 端點（`Api::V1::OwnershipSnapshotsController`），支援 `?range=` 參數過濾
5. 寫 request spec 測試 API 回傳格式

### Phase 3：React 元件實作
1. 實作 `App.jsx`：fetch API（帶 `range` 參數）→ 管理 state（預設 range=1y）
2. 實作 `MetricCards.jsx`：三張卡片 + 季度變化
3. 實作 `TimeRangeSelector.jsx`：四個按鈕（90天 / 季度 / 半年 / 1年），切換時 refetch API
4. 實作 `OwnershipTrendChart.jsx`：Recharts 折線圖 + custom tooltip + fallback
5. 實作 `HoldersTable.jsx`：機構表格 + 季度變化欄 + NEW / 已退出標記
6. 實作 `utils/format.js`：數值格式化 helpers

### Phase 4：整合與收尾
1. 將 React app mount 到持股結構頁面
2. 「抓取快照」按鈕改為呼叫 POST API → 成功後 refetch 資料更新畫面
3. 端對端驗證：抓取 → DB 寫入 → API 回傳 → 畫面更新

---

## 四、注意事項

- **前端架構**：此頁面使用 Vite + React + Recharts，不使用 Phlex
- **圖表庫**：`recharts`（npm install），不要用 Chart.js CDN
- **樣式**：沿用專案 Tailwind CSS 設定
- **不要使用 Hotwire / Stimulus**
- **API 優先**：Rails 只提供 JSON API，所有 UI 邏輯在 React 端處理
- **Migration 跑完後確認 `db/schema.rb` 已更新**
- **每個 Phase 完成後跑測試（rspec for Rails、React 元件可用 jest/vitest），通過才進下一個 Phase**
