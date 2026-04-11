# frozen_string_literal: true

# Shared Markdown rendering logic for controllers that output HTML from LLM text.
# Handles Llama-specific formatting quirks and robust GFM table normalization.
module MarkdownRendering
  extend ActiveSupport::Concern

  private

  def render_gfm(text)
    Kramdown::Document.new(normalize_md_tables(normalize_llama_output(text)), input: "GFM").to_html
  end

  # Fix Llama-specific markdown issues before passing to normalize_md_tables.
  #
  # Handles four Llama output problems:
  #   A) mid-line heading WITHOUT space  ("text##2. Title")  → split + add space
  #   B) mid-line heading WITH space     ("text## Title")    → split
  #   C) heading-start without space     ("##Title")         → add space
  #   D) table or blockquote glued to heading on same line   → split
  #   E) line-by-line: ensure blank line after every heading
  def normalize_llama_output(text) # rubocop:disable Metrics/MethodLength
    # Pass A: mid-line heading WITHOUT space after # ("text##2. Title")
    text = text.gsub(/([^\n])\n?(#+)([^#\s\n])/) { $1 + "\n\n" + $2 + " " + $3 }

    # Pass B: mid-line heading WITH space after # ("text## Title")
    text = text.gsub(/([^\n])(#+\s)/) { $1 + "\n\n" + $2 }

    # Pass C: heading-start without space ("##Title" → "## Title")
    text = text.gsub(/^(#+)([^#\s\n])/) { $1 + " " + $2 }

    # Pass D1: table row glued to end of heading line ("### Heading| col1 |")
    text = text.gsub(/^(#+\s[^|\n]+)\|/) { $1 + "\n\n|" }

    # Pass D2: blockquote glued to non-blank content ("text> quote")
    text = text.gsub(/([^\n])\n?(>\s)/) { $1 + "\n\n" + $2 }

    # Pass E: ensure blank line after every heading line.
    lines  = text.split("\n", -1)
    result = []
    lines.each_with_index do |line, i|
      result << line
      next_line = lines[i + 1]
      result << "" if line.match?(/^#+\s/) && next_line && !next_line.strip.empty?
    end
    result.join("\n")
  end

  # Robust GFM table normalizer.
  #
  # Two-pass approach:
  # 1. Replace every separator row in-place (derive col count from pipe count).
  # 2. Drop blank lines that appear immediately before a separator row.
  def normalize_md_tables(text) # rubocop:disable Metrics/MethodLength
    lines = text.each_line.map do |line|
      if separator_row?(line)
        col_count = line.count("|") - 1
        "|#{"---|" * col_count}\n"
      else
        line
      end
    end

    result = []
    lines.each_with_index do |line, idx|
      next if line.strip.empty? && idx + 1 < lines.length && separator_row?(lines[idx + 1])

      result << line
    end

    result.join
  end

  # A separator row has no Unicode letters or digits — covers every dash variant.
  def separator_row?(line)
    s = line.strip
    s.start_with?("|") && s.end_with?("|") && s.length > 2 &&
      !s.match?(/[\p{L}\p{N}]/)
  end
end
