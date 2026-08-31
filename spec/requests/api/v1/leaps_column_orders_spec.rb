# frozen_string_literal: true

require "rails_helper"

# 欄位順序是全站共用設定：所有人看到同一個順序，所以寫入只開放 admin。
# 這支測試把「非 admin 改不動」與「payload 必須是完整排列」釘住。
RSpec.describe "API::V1::LeapsColumnOrders", :skip_auto_auth, type: :request do
  let(:secret) { "base32secret3232" }
  let(:custom_order) { LeapsTableColumns::DEFAULT_KEYS.rotate(2) }

  def sign_in_and_verify_totp!(user)
    sign_in_as(user)
    post "/two_factor/challenge", params: { code: ROTP::TOTP.new(secret).now }
  end

  def sign_in(admin:)
    user = create(:user, status: :enabled, totp_enabled: true, totp_secret: secret, admin: admin)
    sign_in_and_verify_totp!(user)
    user
  end

  def put_order(keys)
    put "/api/v1/leaps/column_order", params: { column_keys: keys }, as: :json
  end

  it "未登入時回 401，不寫入任何東西" do
    put_order(custom_order)

    expect(response).to have_http_status(:unauthorized)
    expect(ColumnOrder.count).to eq(0)
  end

  it "非 admin 回 403，不寫入任何東西" do
    sign_in(admin: false)

    put_order(custom_order)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to include("error" => "admin_required")
    expect(ColumnOrder.count).to eq(0)
  end

  context "admin" do
    it "寫入成功並持久化，記下修改者" do
      admin = sign_in(admin: true)

      put_order(custom_order)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["column_keys"]).to eq(custom_order)

      record = ColumnOrder.find_by(table_key: ColumnOrder::LEAPS_RANKING)
      expect(record.column_keys).to eq(custom_order)
      expect(record.updated_by_id).to eq(admin.id)
    end

    it "重複寫入更新同一列，不會累積多列" do
      sign_in(admin: true)

      put_order(custom_order)
      put_order(LeapsTableColumns::DEFAULT_KEYS)

      expect(ColumnOrder.count).to eq(1)
      expect(ColumnOrder.keys_for(ColumnOrder::LEAPS_RANKING)).to eq(LeapsTableColumns::DEFAULT_KEYS)
    end

    # 允許缺漏就等於讓前端的一個 bug 永久刪掉欄位，所以寫入路徑要求完整排列。
    it "缺欄位的 payload 回 422" do
      sign_in(admin: true)

      put_order(LeapsTableColumns::DEFAULT_KEYS - %w[iv])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include("error" => "invalid_column_keys")
      expect(ColumnOrder.count).to eq(0)
    end

    it "含未知欄位的 payload 回 422" do
      sign_in(admin: true)

      put_order(LeapsTableColumns::DEFAULT_KEYS + %w[ghost])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ColumnOrder.count).to eq(0)
    end

    it "有重複欄位的 payload 回 422" do
      sign_in(admin: true)

      put_order((LeapsTableColumns::DEFAULT_KEYS - %w[iv]) + %w[vega])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ColumnOrder.count).to eq(0)
    end
  end
end
