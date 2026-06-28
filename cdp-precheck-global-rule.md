# CDP 連線預檢（全域規則）

## 規則

任何 controller action 會觸發 Barchart/Playwright 抓取（CDP）的，都必須在送出背景 job **之前**先檢查 CDP 連線是否可用，檢查失敗要在 1-2 秒內直接回報「CDP 未連線」，**不能讓 job 排進去、等到 scraper 內部才報錯**（曾經發生過：job 跑了 13 秒才在 scraper 內部失敗，使用者白等，而 controller 層級完全沒有先擋）。

這條適用於**所有現在或未來**會用到 CDP 的 controller，不是只套用在單一功能。新功能不需要重新討論「要不要做這個檢查」，預設就要做。

## 環境背景（WSL2 mirrored 網路模式）

這個專案的 Chrome CDP 是在 WSL2 mirrored 網路模式下、Windows 端開啟 Chrome 並指定 `--remote-debugging-port=9222`，WSL2 這邊透過 `localhost:9222` 連線。預檢方式：對 `http://localhost:9222/json/version` 發請求，能連上且回傳版本資訊代表 CDP 可用。

## 實作方式：抽成共用機制，不要每個 controller 各自重寫

**不要**讓每個新 controller 自己寫一段一樣的檢查邏輯——這正是之前反覆出包的原因：規則存在，但要靠每次有人手動記得套用，漏一次就出包一次。

正確做法：抽成一個共用的 concern（例如 `CdpPrecheckable`），用 `before_action` 在會碰 CDP 的 action 之前自動執行，新 controller 只要 `include CdpPrecheckable` 就自動有這層防護。這樣之後新功能少寫這一行，從程式碼上就能立刻看出少了什麼，不需要靠記憶或提醒去抓。

```ruby
# app/controllers/concerns/cdp_precheckable.rb（示意，實際請依專案慣例調整）
module CdpPrecheckable
  extend ActiveSupport::Concern

  included do
    before_action :precheck_cdp_connection, only: cdp_precheck_actions
  end

  class_methods do
    def cdp_precheck_actions
      [:index, :create] # 各 controller 依實際情況覆寫
    end
  end

  private

  def precheck_cdp_connection
    return if cdp_available?

    respond_to do |format|
      format.html { render :cdp_unavailable, status: :service_unavailable }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("status", partial: "shared/cdp_unavailable") }
    end
  end

  def cdp_available?
    Timeout.timeout(2) do
      response = Net::HTTP.get_response(URI("http://localhost:9222/json/version"))
      response.is_a?(Net::HTTPSuccess)
    end
  rescue StandardError
    false
  end
end
```

錯誤訊息文字：「CDP 未連線，請確認 Windows 端 Chrome 已以 `--remote-debugging-port=9222` 啟動，並可在瀏覽器開啟 `http://localhost:9222/json/version` 確認。」

## 驗收標準

- [ ] 新增任何會碰 CDP 的 controller 時，第一步就是 `include CdpPrecheckable`（或專案實際採用的等效機制），不是事後補。
- [ ] CDP 離線時，從使用者點擊到畫面顯示錯誤訊息，在 1-2 秒內完成，不是等 job 跑進 scraper 才失敗。
- [ ] 每個套用這個 concern 的 controller 都有對應測試，覆蓋「CDP 離線時直接擋下、不送 job」這個情境。
