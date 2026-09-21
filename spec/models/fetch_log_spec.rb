# frozen_string_literal: true

require "rails_helper"

# FetchLog 的兩份白名單（FETCH_TYPES／STATUSES）是**稽核記錄能不能寫進 DB** 的關卡。
# 漏掉一個值不會炸：BarchartScraperService#log_fetch 把 validation 例外 rescue 成
# 一行 warn，那筆抓取記錄就安靜地消失了。2026-09-21 發現 volap 與 price_history
# 兩種抓取從上線起一筆都沒進 DB，就是這樣漏掉的。
#
# 所以這裡用稽核測試把白名單釘在原始碼上（做法同 spec/frontend/behavior_registry_spec.rb）：
# 新增 scraper 狀態卻忘了補白名單，會在測試階段就被擋下來，而不是等到有人
# 去翻抓取記錄才發現少了半年。
RSpec.describe FetchLog, type: :model do
  let(:service_file)  { Rails.root.join("app/services/barchart_scraper_service.rb") }
  let(:scraper_files) { Dir[Rails.root.join("lib/barchart_scrapers/*.py")].reject { |f| File.basename(f).start_with?("test_") } }

  # log_fetch("volap", "success", ...) 的第一個參數
  def fetch_types_in_service
    File.read(service_file).scan(/log_fetch\(\s*"([a-z_]+)"/).flatten.uniq.sort
  end

  # log_fetch 第二個參數是字面字串的那些（傳變數的無法靜態掃，見下面的 fallback 測試）
  def statuses_in_service
    File.read(service_file).scan(/log_fetch\(\s*"[a-z_]+",\s*"([a-z_]+)"/).flatten.uniq.sort
  end

  # scraper 輸出 JSON 裡的 "status": "xxx"
  def statuses_in_scrapers
    scraper_files.flat_map { |f| File.read(f).scan(/["']status["']\s*:\s*["']([a-z_]+)["']/).flatten }.uniq.sort
  end

  describe "白名單涵蓋實際用到的值" do
    it "service 裡 log_fetch 用到的 fetch_type 都有列進 FETCH_TYPES" do
      used = fetch_types_in_service
      expect(used).not_to be_empty, "掃不到任何 log_fetch 呼叫，測試本身可能失效了"

      missing = used - described_class::FETCH_TYPES
      expect(missing).to be_empty, "這些 fetch_type 沒列進 FetchLog::FETCH_TYPES：#{missing.join(', ')}"
    end

    it "service 裡 log_fetch 用到的 status 都有列進 STATUSES" do
      used = statuses_in_service
      expect(used).not_to be_empty, "掃不到任何字面 status，測試本身可能失效了"

      missing = used - described_class::STATUSES
      expect(missing).to be_empty, "這些 status 沒列進 FetchLog::STATUSES：#{missing.join(', ')}"
    end

    it "python scraper 會回傳的 status 都有列進 STATUSES" do
      used = statuses_in_scrapers
      expect(used).not_to be_empty, "掃不到任何 scraper status，測試本身可能失效了"

      missing = used - described_class::STATUSES
      expect(missing).to be_empty, "這些 scraper status 沒列進 FetchLog::STATUSES：#{missing.join(', ')}"
    end

    # volap_scraper.py 的狀態是用 `return None, "no_volap_plot"` 這種寫法傳出來的，
    # 上面的 JSON 掃描抓不到，只能明列。run_scraper 的 else 分支會把它們原樣往上傳。
    it "volap 的四個特殊狀態都在 STATUSES 裡" do
      %w[no_volap_plot volap_timeout chart_not_ready logged_out].each do |status|
        next if status == "logged_out" # scraper 內部狀態，對外轉成 barchart_session_expired

        expect(described_class::STATUSES).to include(status),
          "volap_scraper.py 會回 #{status}，但 FetchLog::STATUSES 沒有"
      end
    end
  end

  describe "BarchartScraperService#log_fetch" do
    let(:service) { BarchartScraperService.new("TSTX") }

    it "正常狀態照實寫入" do
      expect {
        service.send(:log_fetch, "volap", "success", "bins=24")
      }.to change(described_class, :count).by(1)

      log = described_class.last
      expect(log.fetch_type).to eq("volap")
      expect(log.status).to eq("success")
    end

    # scraper 日後新增狀態時的安全網：記不進去就等於那次抓取沒發生過。
    it "白名單外的狀態降級成 error 寫入，原值留在 error_detail" do
      expect {
        service.send(:log_fetch, "volap", "brand_new_status", "some detail")
      }.to change(described_class, :count).by(1)

      log = described_class.last
      expect(log.status).to eq("error")
      expect(log.error_detail).to include("unmapped_status=brand_new_status")
      expect(log.error_detail).to include("some detail")
    end

    it "降級時 detail 是 nil 也不會爆" do
      expect {
        service.send(:log_fetch, "volap", "brand_new_status", nil)
      }.to change(described_class, :count).by(1)

      expect(described_class.last.error_detail).to eq("unmapped_status=brand_new_status")
    end
  end
end
