# frozen_string_literal: true

class TranslationService
  ENDPOINT  = "https://api.mymemory.translated.net/get"
  CACHE_TTL = 30.days

  def translate(text, to: "zh-TW")
    return text if text.blank?

    cache_key = "translation:#{Digest::MD5.hexdigest("#{to}:#{text}")}"
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      fetch_translation(text, to: to)
    end
  end

  def translate_as_markdown(text)
    return "" if text.blank?

    cache_key = "translation:#{Digest::MD5.hexdigest("zh-TW:#{text}")}"
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      fetch_translation(text, to: "zh-TW")
    end
  end

  private

  def fetch_translation(text, to:)
    response = HTTParty.get(
      ENDPOINT,
      query:   { q: text, langpair: "en|#{to}" },
      timeout: 6
    )
    return text unless response.success?

    translated = response.parsed_response.dig("responseData", "translatedText")
    translated.present? ? translated : text
  rescue StandardError => e
    Rails.logger.warn("[TranslationService] #{e.message}")
    text
  end
end
