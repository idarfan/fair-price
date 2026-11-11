# frozen_string_literal: true

module HallOfFame
  # needs_review filing 以 insert_all 寫入、保留原值（P3 質詢 5），可能有不合 model 驗證的列。
  # 這裡判斷一列能不能列入佔比；不能的照原值顯示並附原因（P5，使用者裁示：只排除問題列）。
  module RowCheck
    module_function

    # 回傳排除原因（字串）或 nil。原因帶申報原字串，讓畫面看得到原值（P5 r1 問題 1）。
    def exclusion_reason(asset_name:, owner:, min:, label:)
      return "金額無法對照（#{label.to_s.inspect.tr('"', "'")}）" if min.nil?
      return "持有人代碼未知（#{owner.inspect}）" unless Holding::OWNERS.include?(owner)
      return "資產名稱空白" if asset_name.blank?

      nil
    end
  end
end
