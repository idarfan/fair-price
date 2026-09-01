# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::PmccPositions", type: :request do
  let(:user) { signed_in_user }
  let(:position) do
    create(:pmcc_position, user: user, long_strike: 100, long_entry_cost: 120.5, long_contracts: 1)
  end
  let!(:open_leg) do
    create(:pmcc_short_leg, position: position, short_strike: 230,
                            premium_collected: 3.2, contracts: 1, status: "open")
  end

  describe "POST /api/v1/pmcc_positions" do
    let(:valid_params) do
      { ticker: "be", long_contracts: 2, long_strike: 100, long_expiration: "2028-01-21",
        long_entry_cost: 120.5, long_entry_date: Date.current.to_s }
    end

    it "建立部位並綁到目前使用者" do
      expect { post "/api/v1/pmcc_positions", params: valid_params, as: :json }
        .to change(user.pmcc_positions, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(user.pmcc_positions.last.ticker).to eq("BE")
    end

    it "缺必填回 422" do
      post "/api/v1/pmcc_positions", params: valid_params.except(:long_strike), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "隔離" do
    let(:other_position) { create(:pmcc_position, user: create(:user)) }

    it "改不到別人的部位（RecordNotFound → 404）" do
      post "/api/v1/pmcc_positions/#{other_position.id}/expire", as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "刪不掉別人的部位" do
      other_position   # 先建立

      expect { delete "/api/v1/pmcc_positions/#{other_position.id}", as: :json }
        .not_to change(PmccPosition, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST roll" do
    let(:roll_params) do
      { close_cost: 1.1, new_strike: 240, new_expiration: (Date.current + 45).to_s, new_premium: 4.0 }
    end

    def do_roll(params = roll_params)
      post "/api/v1/pmcc_positions/#{position.id}/roll", params: params, as: :json
    end

    it "舊腳標記 rolled 並記錄買回成本" do
      do_roll

      expect(response).to have_http_status(:ok)
      expect(open_leg.reload.status).to eq("rolled")
      expect(open_leg.close_cost).to eq(1.1)
    end

    it "開出新短腳並接上 roll 鏈" do
      expect { do_roll }.to change(position.short_legs, :count).by(1)

      new_leg = position.short_legs.open_legs.first
      expect(new_leg.short_strike).to eq(240)
      expect(open_leg.reload.rolled_to).to eq(new_leg)
    end

    # 金額用 PmccPnlService 的公式，不在 controller 重寫一份
    it "寫入 short_closed 事件，金額 = (收租 − 買回) × 口數 × 100 − 手續費" do
      do_roll(roll_params.merge(fees: 2.6))

      event = position.pnl_events.last
      expect(event.event_type).to eq("short_closed")
      expect(event.realized_pnl).to eq((3.2 - 1.1) * 100 - 2.6)
    end

    it "留存當下報價供日後回溯（快照是覆蓋式的，事後查不到）" do
      do_roll

      expect(position.pnl_events.last.quote_snapshot["close_cost"]).to eq(1.1)
    end

    it "沒有未平倉短腳時回 422" do
      open_leg.update!(status: "rolled", close_cost: 1.1)

      do_roll
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "缺 close_cost 回 422（不假設買回成本為 0）" do
      do_roll(roll_params.except(:close_cost))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # 中途失敗留下「舊腳關了、新腳沒開」會讓帳本永遠對不起來
    it "新腳資料不合法時整段回滾，舊腳維持 open、不留下事件" do
      expect { do_roll(roll_params.merge(new_strike: nil)) }
        .not_to change(PmccPnlEvent, :count)

      expect(open_leg.reload.status).to eq("open")
      expect(position.short_legs.count).to eq(1)
    end
  end

  describe "POST expire" do
    it "收租全數落袋，短腳標記 expired_worthless" do
      post "/api/v1/pmcc_positions/#{position.id}/expire", as: :json

      expect(position.pnl_events.last.realized_pnl).to eq(320.0)
      expect(open_leg.reload.status).to eq("expired_worthless")
    end
  end

  describe "POST assign" do
    it "只記短腳自己的現金流，不含長腳估算" do
      post "/api/v1/pmcc_positions/#{position.id}/assign",
           params: { close_cost: 2.0 }, as: :json

      event = position.pnl_events.last
      expect(event.event_type).to eq("short_assigned")
      expect(event.realized_pnl).to eq((3.2 - 2.0) * 100)
    end
  end

  describe "POST close（兩腳一起平倉）" do
    def do_close(params = { long_sell_price: 130.0, short_close_cost: 1.1 })
      post "/api/v1/pmcc_positions/#{position.id}/close", params: params, as: :json
    end

    it "寫入長腳與短腳兩筆事件" do
      expect { do_close }.to change(position.pnl_events, :count).by(2)

      expect(position.pnl_events.pluck(:event_type)).to contain_exactly("short_closed", "long_closed")
    end

    it "長腳損益 = (賣出價 − 實付成本) × 口數 × 100" do
      do_close

      long_event = position.pnl_events.find_by(event_type: "long_closed")
      expect(long_event.realized_pnl).to eq((130.0 - 120.5) * 100)
    end

    it "部位狀態轉為 closed 並記錄時間" do
      do_close

      expect(position.reload.status).to eq("closed")
      expect(position.closed_at).to be_present
    end

    it "沒有未平倉短腳時只記長腳那筆" do
      open_leg.update!(status: "expired_worthless", close_cost: 0)

      expect { do_close }.to change(position.pnl_events, :count).by(1)
    end

    it "缺 long_sell_price 回 422" do
      do_close({ short_close_cost: 1.1 })

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE" do
    it "刪除部位會一併清掉短腳與帳本" do
      create(:pmcc_pnl_event, position: position)

      expect { delete "/api/v1/pmcc_positions/#{position.id}", as: :json }
        .to change(PmccPosition, :count).by(-1)
        .and change(PmccShortLeg, :count).by(-1)
        .and change(PmccPnlEvent, :count).by(-1)
    end
  end
end
