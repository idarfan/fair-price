# frozen_string_literal: true

class FlightChatService
  API_URL    = "https://api.anthropic.com/v1/messages"
  MODEL      = "claude-sonnet-4-6"
  SKILL_PATH = Pathname.new("/home/idarfan/.claude/skills/tw-japan-flight-expert/tw-japan-flight-expert.md")

  def self.system_prompt
    @system_prompt ||= begin
      raw = SKILL_PATH.read
      # Strip YAML frontmatter (--- ... ---)
      raw.sub(/\A---\n.*?\n---\n/m, "").strip
    end
  end

  # @param user_message [String]
  # @param history [Array<Hash>]  e.g. [{role: "user", content: "..."}, {role: "assistant", content: "..."}]
  # @return [String] markdown text from Claude
  def call(user_message, history = [])
    messages = history.map { |m| { role: m[:role] || m["role"], content: m[:content] || m["content"] } }
    messages << { role: "user", content: user_message }

    response = HTTParty.post(
      API_URL,
      headers: {
        "x-api-key"         => ENV.fetch("ANTHROPIC_API_KEY"),
        "anthropic-version" => "2023-06-01",
        "content-type"      => "application/json"
      },
      body: {
        model:      MODEL,
        max_tokens: 4096,
        system:     self.class.system_prompt,
        messages:   messages
      }.to_json,
      timeout: 90
    )

    raise "Anthropic API 錯誤 (HTTP #{response.code})" unless response.success?

    response.parsed_response.dig("content", 0, "text") ||
      raise("API 回傳格式異常")
  end
end
