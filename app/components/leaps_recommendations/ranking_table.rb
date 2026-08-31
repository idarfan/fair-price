# frozen_string_literal: true

module LeapsRecommendations::RankingTable
  include LeapsRecommendations::SharedConstants

  # 欄位定義（有哪些欄、叫什麼）在 LeapsTableColumns；顯示順序由 ColumnOrder
  # 決定（admin 可在頁面上拖曳調整，全站套用）。兩者刻意分開：這支 component
  # 只負責「照這個順序畫出來」。
  def ordered_col_keys
    @ordered_col_keys ||= ColumnOrder.keys_for(ColumnOrder::LEAPS_RANKING)
  end


  # 只有 admin 能拖曳調整欄位順序（順序是全站設定，不是個人偏好）。
  # 這裡只決定「要不要把拖曳掛勾渲染出來」，真正的權限判斷在
  # Api::V1::LeapsColumnOrdersController#require_admin!，前端拿掉屬性也繞不過。
  def col_reorder_enabled?
    helpers.respond_to?(:current_user) && helpers.current_user&.admin?
  end


  # 欄位篩選面板：每欄一個 checkbox，預設勾選（DEFAULT_HIDDEN_KEYS 除外），
  # 由 render_price_estimator_script 內的委派 click handler 監聽 change 事件切換
  # 對應 [data-col] 元素的 leaps-col-hidden class，讓表格不必整段重新渲染。
  def render_column_toggle_panel
    div(class: "leaps-col-toggle-panel") do
      ordered_col_keys.each do |key|
        checked = !LeapsTableColumns::DEFAULT_HIDDEN_KEYS.include?(key)
        label do
          input(type: "checkbox", class: "leaps-col-toggle-checkbox", data_col: key, checked: checked)
          plain LeapsTableColumns::LABELS[key]
        end
      end
    end
  end


  def render_ranking_table
    div(class: "bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden") do
      div(class: "px-4 py-3 border-b border-gray-100 bg-gray-50") do
        h2(class: "text-sm font-semibold text-gray-700") { plain "LEAPS 候選排行 — #{@symbol}" }
        p(class: "text-xs text-gray-400 mt-0.5") do
          plain "依 OI 由高到低排序；流動性判斷依本次查詢候選的 OI 相對排名計算，非固定門檻，不同標的會自動調整基準。"
        end
        if col_reorder_enabled?
          p(class: "text-xs text-blue-500 mt-0.5", data_export_exclude: "") do
            plain "（管理員）按住表頭左右拖曳可調整欄位順序，放開即儲存，全站套用。"
          end
        end
        render_column_toggle_panel
      end
      div(class: "overflow-x-auto") do
        table(**ranking_table_attrs) do
          thead(class: "bg-gray-50 text-gray-500 text-xs") do
            tr do
              ordered_col_keys.each { |key| render_ranking_th(key) }
            end
          end
          tbody do
            @candidates.each_with_index { |row, i| render_candidate_row(row, i) }
          end
        end
      end
      div(class: "px-4 py-2 border-t border-gray-100 bg-gray-50") do
        p(class: "text-xs text-gray-400") do
          plain "以上為 Delta 區間篩選後的排行結果，僅供策略篩選參考，非投資建議，請自行評估。"
        end
      end
    end
  end


  def ranking_table_attrs
    attrs = { id: "leaps-ranking-table", class: "w-full text-xs text-gray-700" }
    return attrs unless col_reorder_enabled?

    attrs.merge(
      data_col_reorder: "1",
      data_col_reorder_url: helpers.api_v1_leaps_column_order_path,
      data_col_reorder_csrf: helpers.form_authenticity_token
    )
  end


  def render_ranking_th(key)
    th(id: "leaps-th-#{key}", data_tip_key: key, data_col: key,
       class: "px-3 py-2 text-center font-medium whitespace-nowrap#{hidden_col_class(key)}") do
      plain LeapsTableColumns::LABELS[key]
      if (sub = LeapsTableColumns::SUBLABELS[key])
        div(class: "text-[10px] font-normal text-gray-400") { plain sub }
      end
    end
  end


  # 使用者在履約價輸入框填的值，是否就是這一列——用來在完整排行表裡標出來，
  # 讓使用者一眼看到「我查的那檔」，不管它有沒有被選進上面的推薦分析。
  def user_strike_row?(row)
    @user_strike.present? && row[:strike].present? &&
      row[:strike].to_f == @user_strike.to_f
  end


  # 使用者指定的履約價流動性不足時的原因文字（供「不建議」標籤旁顯示）。
  # 只在 user_strike_row? 為真時呼叫。
  def not_recommended_reason(row)
    return "近期無成交紀錄，進出場可能有困難" if row[:no_recent_volume_warning]
    return "OI 在本次候選中排名偏低，流動性相對較差" if row[:liquidity_tier].to_s == "偏低"

    nil
  end


  def render_candidate_row(row, i)
    mine     = user_strike_row?(row)
    not_reco = mine ? not_recommended_reason(row) : nil

    row_class = "border-t border-gray-100 hover:bg-purple-200 #{i.odd? ? 'bg-gray-50/50' : ''}"
    row_class += " bg-blue-50/70 ring-1 ring-inset ring-blue-300" if mine

    cells = candidate_cell_renderers(row, mine: mine, not_reco: not_reco)

    tr(class: row_class) do
      ordered_col_keys.each { |key| cells.fetch(key).call }
    end
  end


  # 每個欄位一支渲染 lambda：欄位順序可變，td 就不能再寫死成一長串順序呼叫。
  # key 與 LeapsTableColumns::DEFAULT_KEYS 一一對應，缺一個就會在
  # render_candidate_row 的 fetch 直接炸掉（比默默少一欄好抓）。
  def candidate_cell_renderers(row, mine:, not_reco:)
    {
      "price_estimate" => -> { render_price_estimate_cell(row) },
      "expiration"     => -> { td(class: "px-3 py-2 text-center font-mono whitespace-nowrap", data_col: "expiration") { plain row[:expiration_date].to_s } },
      "dte"            => -> { td(class: "px-3 py-2 text-center", data_col: "dte") { plain row[:dte].to_s } },
      "strike"         => -> { render_strike_cell(row, mine) },
      "delta"          => -> { td(class: "px-3 py-2 text-center", data_col: "delta") { plain fmt_decimal(row[:delta], 4) } },
      "oi"             => -> { td(class: "px-3 py-2 text-center font-semibold", data_col: "oi") { plain fmt_int(row[:open_interest]) } },
      "volume"         => -> { td(class: "px-3 py-2 text-center", data_col: "volume") { plain fmt_int(row[:volume]) } },
      "liquidity"      => -> { render_liquidity_cell(row, not_reco) },
      "bid"            => -> { td(class: "px-3 py-2 text-center", data_col: "bid") { plain fmt_price(row[:bid]) } },
      "ask"            => -> { td(class: "px-3 py-2 text-center", data_col: "ask") { plain fmt_price(row[:ask]) } },
      "mid"            => -> { td(class: "px-3 py-2 text-center", data_col: "mid") { plain fmt_price(row[:mid]) } },
      "spread"         => -> { td(class: "px-3 py-2 text-center", data_col: "spread") { plain fmt_pct(row[:bid_ask_spread_pct]) } },
      "intrinsic"      => -> { td(class: "px-3 py-2 text-center", data_col: "intrinsic") { plain fmt_price(row[:intrinsic_value]) } },
      "extrinsic"      => -> { td(class: "px-3 py-2 text-center", data_col: "extrinsic") { plain fmt_price(row[:extrinsic_value]) } },
      "extrinsic_pct"  => -> { td(class: "px-3 py-2 text-center font-semibold", data_col: "extrinsic_pct") { plain fmt_pct(row[:extrinsic_pct]) } },
      "time_value_pct" => -> { td(class: "px-3 py-2 text-center", data_col: "time_value_pct") { plain fmt_pct(row[:time_value_pct]) } },
      "iv"             => -> { td(class: "px-3 py-2 text-center #{iv_color_class(row[:iv])}", data_col: "iv") { plain fmt_pct(row[:iv]) } },
      "vega"           => -> { td(class: "px-3 py-2 text-center", data_col: "vega") { plain fmt_decimal(row[:vega], 4) } },
      "itm_prob"       => -> { td(class: "px-3 py-2 text-center#{hidden_col_class('itm_prob')}", data_col: "itm_prob") { plain fmt_pct(row[:itm_probability]) } }
    }
  end


  def render_price_estimate_cell(row)
    td(class: "px-3 py-2 text-center", data_col: "price_estimate") do
      button(
        type: "button",
        class: "leaps-price-estimate-btn px-2 py-1 rounded border border-gray-300 text-xs text-gray-600 " \
               "hover:bg-gray-100 whitespace-nowrap",
        data_strike: row[:strike].to_s,
        data_underlying: row[:underlying_price].to_s,
        data_iv: (row[:iv].to_f * 100).to_s,
        data_dte: row[:dte].to_s,
        data_expiration: row[:expiration_date].to_s,
        data_mid: row[:mid].to_s
      ) { plain "📈 試算" }
    end
  end


  def render_strike_cell(row, mine)
    td(class: "px-3 py-2 text-center font-semibold", data_col: "strike") do
      div(class: "inline-flex flex-col items-center gap-0.5") do
        span { plain fmt_price(row[:strike]) }
        if mine
          span(class: "text-blue-600 text-[10px] font-normal whitespace-nowrap") { plain "★ 你查詢的履約價" }
        end
      end
    end
  end


  def render_liquidity_cell(row, not_reco)
    tier  = row[:liquidity_tier].to_s
    style = LIQUIDITY_STYLE[tier] || LIQUIDITY_STYLE["普通"]
    warn  = row[:no_recent_volume_warning]

    td(class: "px-3 py-2 text-center", data_col: "liquidity") do
      div(class: "inline-flex flex-col items-center gap-1") do
        div(class: "inline-flex flex-row items-center gap-1.5") do
          span(class: "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs " \
                       "#{style[:bg]} #{style[:text]} border #{style[:border]}") do
            div(class: "w-1.5 h-1.5 rounded-full flex-shrink-0 #{style[:dot]}")
            plain tier
          end
          if warn
            span(class: "text-orange-600 text-xs whitespace-nowrap") { plain "⚠ 近期無成交" }
          end
        end
        if not_reco
          span(class: "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs " \
                       "bg-red-50 text-red-600 border border-red-200 whitespace-nowrap") do
            plain "🚫 不建議：#{not_reco}"
          end
        end
      end
    end
  end


  # td 版本的預設隱藏 class（th 版本邏輯見 render_ranking_th），
  # 兩處都讀同一份 DEFAULT_HIDDEN_KEYS，避免表頭/表身初始狀態不同步。
  def hidden_col_class(key)
    LeapsTableColumns::DEFAULT_HIDDEN_KEYS.include?(key) ? " leaps-col-hidden" : ""
  end
end
