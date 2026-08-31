# frozen_string_literal: true

# LEAPS 候選排行表的欄位定義：唯一真實來源。
#
# 欄位順序可由 admin 在頁面上拖曳調整（存進 column_orders），所以「有哪些欄位、
# 各自叫什麼」必須跟「這次要用什麼順序顯示」分開：這裡只管前者，順序由
# ColumnOrder 決定。Component、PDF payload、API 驗證三邊都讀這一份，避免
# 各自帶一份欄位清單而漂移。
class LeapsTableColumns
  # 預設順序（＝過去寫死在 RankingTable::TABLE_COLS 的順序）。
  DEFAULT_KEYS = %w[
    price_estimate expiration dte strike delta oi volume liquidity bid ask mid spread
    intrinsic extrinsic extrinsic_pct time_value_pct iv vega itm_prob
  ].freeze

  LABELS = {
    "price_estimate"  => "價格預估",
    "expiration"      => "到期日",
    "dte"             => "DTE",
    "strike"          => "履約價",
    "delta"           => "Delta",
    "oi"              => "OI",
    "volume"          => "Volume",
    "liquidity"       => "流動性判斷",
    "bid"             => "Bid",
    "ask"             => "Ask",
    "mid"             => "Mid",
    "spread"          => "Spread%",
    "intrinsic"       => "內在價值",
    "extrinsic"       => "外在價值",
    "extrinsic_pct"   => "外在佔比",
    "time_value_pct"  => "Time Value%",
    "iv"              => "IV",
    "vega"            => "Vega",
    "itm_prob"        => "被指派機率"
  }.freeze

  # 表頭中文註記：只在 th 底下多渲染一行小字，不併進 LABELS 的欄名。
  # 併進欄名會讓該欄（th 是 whitespace-nowrap）被撐寬，把「流動性判斷」擠到換行。
  SUBLABELS = { "spread" => "買賣差價比" }.freeze

  # 欄位篩選面板預設不勾選的欄位：讓表格初次呈現不那麼擁擠，使用者可自行勾回來。
  DEFAULT_HIDDEN_KEYS = %w[itm_prob].freeze

  # PDF 表格不印「價格預估」——那一欄是試算按鈕，平面文件上沒有意義。
  PDF_EXCLUDED_KEYS = %w[price_estimate].freeze

  raise "LABELS 未覆蓋所有 DEFAULT_KEYS" unless (DEFAULT_KEYS - LABELS.keys).empty?
  raise "LABELS 有 DEFAULT_KEYS 以外的 key" unless (LABELS.keys - DEFAULT_KEYS).empty?

  # 把「存起來的順序」修成一定合法的順序。
  #
  # 存進 DB 的順序是當下那批欄位的快照，日後程式加了新欄位、或欄位被移除，
  # 舊快照就會對不上。規則：
  #   1. 先丟掉已經不存在的 key，並去重
  #   2. 再把缺漏的 key 依 DEFAULT_KEYS 的原本位置插回去
  # 所以新增欄位不需要動資料，也不會因為舊順序而整欄消失。
  def self.sanitize(stored)
    kept = Array(stored).map(&:to_s).uniq.select { |k| DEFAULT_KEYS.include?(k) }
    return DEFAULT_KEYS.dup if kept.empty?

    missing = DEFAULT_KEYS - kept
    missing.each_with_object(kept.dup) do |key, acc|
      acc.insert(insert_position_for(key, acc), key)
    end
  end

  # 缺漏欄位要插在哪：找出預設順序裡排在它前面、且目前已在列表中的最後一個欄位，
  # 插到那個欄位後面；都不在就插在最前面。
  def self.insert_position_for(key, current)
    preceding = DEFAULT_KEYS[0...DEFAULT_KEYS.index(key)]
    anchor = preceding.reverse.find { |k| current.include?(k) }
    anchor ? current.index(anchor) + 1 : 0
  end
  private_class_method :insert_position_for
end
