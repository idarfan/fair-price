# frozen_string_literal: true

# LEAPS 垂直價差：同一個標的的 chain 抓取互斥（leaps-call-spread-spec 功能定義 5）。
#
# PostgreSQL session 層級的 advisory lock：連點、多個分頁同時要抓同一個標的時，
# 後來的請求在這裡等待，拿到鎖之後由呼叫端重新檢查快取，直接共用前一次抓取的
# 結果，不再啟動新的 sidecar。只給垂直價差用，不與 bcvs 共用（使用者裁示）。
#
# 鎖綁在連線上，所以整段都在同一條 connection 內執行；ensure 一定解鎖，
# 例外（包含停滯逾時）不會把鎖留在連線池裡。
class LeapsSpreadFetchLock
  NAMESPACE = "leaps_spread_fetch:"

  def self.with(symbol)
    ActiveRecord::Base.connection_pool.with_connection do |conn|
      key = conn.quote("#{NAMESPACE}#{symbol.to_s.strip.upcase}")
      conn.execute("SELECT pg_advisory_lock(hashtext(#{key}))")
      begin
        yield
      ensure
        conn.execute("SELECT pg_advisory_unlock(hashtext(#{key}))")
      end
    end
  end
end
