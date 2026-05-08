# frozen_string_literal: true

require "net/http"
require "json"

class IvSidecarService
  SIDECAR_URL = "http://127.0.0.1:5050"
  TIMEOUT_SECS = 15

  UnavailableError = Class.new(StandardError)
  RequestError     = Class.new(StandardError)

  def self.fetch_atm_iv(ticker)
    new.post("/fetch_atm_iv", { ticker: ticker.to_s.upcase.strip })
  end

  def self.fetch_option_detail(ticker:, strike:, expiry_date:, option_type:)
    new.post("/fetch_option_detail", {
      ticker:      ticker.to_s.upcase.strip,
      strike:      strike.to_f,
      expiry_date: expiry_date.to_s,
      option_type: option_type.to_s.downcase
    })
  end

  def self.fetch_expirations(ticker)
    new.get("/expirations/#{ticker.to_s.upcase.strip}")
  end

  def self.fetch_skew(ticker)
    new.get("/skew/#{ticker.to_s.upcase.strip}")
  end

  def get(path)
    uri  = URI("#{SIDECAR_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = TIMEOUT_SECS
    http.read_timeout = TIMEOUT_SECS

    req = Net::HTTP::Get.new(uri, "Accept" => "application/json")

    begin
      res = http.request(req)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout => e
      raise UnavailableError, "IV sidecar unavailable: #{e.message}"
    end

    body = JSON.parse(res.body, symbolize_names: true)
    raise RequestError, body[:error] || "sidecar error (#{res.code})" unless res.is_a?(Net::HTTPSuccess)
    body
  end

  def post(path, payload)
    uri  = URI("#{SIDECAR_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = TIMEOUT_SECS
    http.read_timeout = TIMEOUT_SECS

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = payload.to_json

    begin
      res = http.request(req)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout => e
      raise UnavailableError, "IV sidecar unavailable: #{e.message}"
    end

    body = JSON.parse(res.body, symbolize_names: true)

    unless res.is_a?(Net::HTTPSuccess)
      raise RequestError, body[:error] || "sidecar error (#{res.code})"
    end

    body
  end
end
