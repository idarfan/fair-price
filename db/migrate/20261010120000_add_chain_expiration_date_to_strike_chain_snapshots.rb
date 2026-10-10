# frozen_string_literal: true

# strikes 讀自哪個 LEAPS 到期日（leaps_scraper.py 的 chain_snapshot["expiration"]）。
# 「期權鏈無此履約價」的訊息與判斷都以它為準；退回近月清單的快照與舊快照為 NULL，
# controller 不拿那些快照判斷掛牌（leaps-deep-itm-fix.md P3 r1 質詢 1、3）。
class AddChainExpirationDateToStrikeChainSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :strike_chain_snapshots, :chain_expiration_date, :date
  end
end
