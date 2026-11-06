# frozen_string_literal: true

module HallOfFame
  # Q2：下載 pending 的 OGE 278e，交給 oge_parser.py 解析 Part 2／5／6，寫入 hof_holdings。
  # 下載、存檔（.part＋rename）、needs_review／failed 界線、逐筆隔離都沿用 HousePdfParse。
  # 278-T（oge_278t）留給 Q3，不在這裡處理。
  # parse_error 第一行固定為文字層判定「textlayer: …」（規格 Q2），其後才是 needs_review 原因。
  class OgePdfParse < HousePdfParse
    SOURCE      = OgeIndexSync::SOURCE
    STORAGE_DIR = Rails.root.join("storage/hall_of_fame/oge")
    KINDS       = { "oge_278e" => "annual" }.freeze

    def initialize(sidecar: OgeParserSidecar.new, pause_seconds: 1, **)
      super
    end

    def pending_scope = Filing.where(source: SOURCE, filing_type: KINDS.keys, parse_status: "pending")

    private

    def parse_error_for(result)
      layer = result.fetch("textlayer")
      header = format("textlayer: %<ratio>.2f%%（%<usable>s）", ratio: layer.fetch("ratio") * 100,
                                                               usable: layer.fetch("usable") ? "可用" : "不可用")
      [ header, *result.fetch("reasons") ].join("\n")
    end
  end
end
