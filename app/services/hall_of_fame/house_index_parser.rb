# frozen_string_literal: true

require "open3"

module HallOfFame
  # 把 House 年度索引 ZIP（內含 {year}FD.xml）解析成 Member 清單。
  # rubyzip 只在 test 群組（selenium-webdriver 的相依），production 載不到，故用系統 unzip。
  class HouseIndexParser
    class Error < StandardError; end

    Member = Data.define(:last, :first, :filing_type, :state_dst, :year, :filing_date, :doc_id)

    def parse(zip_bytes, year)
      xml = extract_xml(zip_bytes, "#{year}FD.xml")
      doc = Nokogiri::XML(xml) { |config| config.strict }
      doc.xpath("//Member").map { |node| member_from(node) }
    rescue Nokogiri::XML::SyntaxError => e
      raise Error, "#{year}FD.xml 不是合法 XML：#{e.message}"
    end

    private

    def extract_xml(zip_bytes, entry_name)
      Tempfile.create([ "hof_house_index", ".zip" ], binmode: true) do |file|
        file.write(zip_bytes)
        file.flush
        out, err, status = Open3.capture3("unzip", "-p", file.path, entry_name, binmode: true)
        raise Error, "解壓 #{entry_name} 失敗：#{err.strip.presence || "exit #{status.exitstatus}"}" unless status.success?

        out.force_encoding(Encoding::UTF_8)
      end
    end

    def member_from(node)
      text = ->(tag) { node.at_xpath(tag)&.text.to_s.strip }
      Member.new(
        last:        text.("Last"),
        first:       text.("First"),
        filing_type: text.("FilingType"),
        state_dst:   text.("StateDst"),
        year:        text.("Year").presence&.to_i,
        filing_date: parse_date(text.("FilingDate")),
        doc_id:      text.("DocID")
      )
    end

    # 索引日期格式為 M/D/YYYY；格式不符回 nil，由同步端記入警示。
    def parse_date(value)
      Date.strptime(value, "%m/%d/%Y")
    rescue Date::Error
      nil
    end
  end
end
