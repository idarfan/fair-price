# frozen_string_literal: true

# 全域 CDP 預檢（CLAUDE.md「CDP 預檢（全域強制）」規則）：任何會排 Barchart/
# Playwright CDP 抓取 job 的 controller action，必須在排 job 之前先確認 CDP
# 連得上，連不上就直接回報、不排 job——不讓使用者等 job 逾時才知道。
#
# 只負責回報，不嘗試自動修復：CDP 離線常見原因是電腦睡眠/喚醒後 WSL2 的
# /mnt/c/ 掛載失效，正確解法是在 Windows PowerShell 執行 wsl --shutdown，
# 這一步只能由外部手動觸發，Rails process 跑在 WSL2 內部無法自己叫外面的
# Windows PowerShell 關掉自己所在的環境。
module CdpPrecheckable
  extend ActiveSupport::Concern

  CDP_VERSION_URL      = "http://127.0.0.1:9222/json/version"
  CDP_PRECHECK_TIMEOUT = 2 # seconds

  CDP_OFFLINE_MESSAGE = (
    "CDP 未連線，請確認 Windows 端 Chrome 已以 `--remote-debugging-port=9222` 啟動。" \
    "若電腦曾經睡眠/喚醒，這通常是 WSL2 的 `/mnt/c/` 掛載失效造成的，請在 Windows " \
    "PowerShell 執行 `wsl --shutdown` 後等待 WSL2 重新啟動，再重試一次。"
  ).freeze

  private

  def cdp_online?
    require "net/http"
    uri  = URI(CDP_VERSION_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = CDP_PRECHECK_TIMEOUT
    http.read_timeout = CDP_PRECHECK_TIMEOUT
    http.get(uri.path).is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end
end
