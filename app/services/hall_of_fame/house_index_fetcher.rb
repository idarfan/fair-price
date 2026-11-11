# frozen_string_literal: true

module HallOfFame
  # 以條件式請求（§1-10）下載 House 年度索引 ZIP。
  # 回 304 → not_modified，沿用上次的 validators；回 200 → 帶回內容與新的 ETag／Last-Modified。
  class HouseIndexFetcher
    class Error < StandardError; end

    Result = Data.define(:status, :body, :validators) do
      def not_modified? = status == :not_modified
    end

    TIMEOUT_SECONDS = 60
    USER_AGENT      = "FairPrice-HallOfFame/1.0"

    def fetch(url, previous_validators = nil)
      previous = previous_validators.to_h
      response = HTTParty.get(url, headers: request_headers(previous), timeout: TIMEOUT_SECONDS, format: :plain)

      case response.code
      when 304 then Result.new(status: :not_modified, body: nil, validators: previous)
      when 200 then Result.new(status: :ok, body: response.body, validators: validators_from(response))
      else raise Error, "#{url} 回應 HTTP #{response.code}"
      end
    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED,
           Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Error, "#{url} 下載失敗：#{e.class}: #{e.message}"
    end

    private

    def request_headers(previous)
      {
        "User-Agent"        => USER_AGENT,
        "If-None-Match"     => previous["etag"],
        "If-Modified-Since" => previous["last_modified"]
      }.compact
    end

    def validators_from(response)
      { "etag" => response.headers["etag"], "last_modified" => response.headers["last-modified"] }.compact
    end
  end
end
