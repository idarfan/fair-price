# frozen_string_literal: true

# pm2 cron 提早觸發的判斷（leaps-iv-environment.md P7.1）。
#
# pm2 6.0.14 內建 croner 4.1.97：setTimeout 到期就執行、不檢查牆上時鐘。本機 WSL2 牆上時鐘比 monotonic
# 慢 3–7%，所以每次排定時間前會被提早觸發 2–3 次（2026-11-07 實例：05:15:56、05:57:30、05:59:50、06:00:00 UTC）。
#
# 判斷：現在離下一次排定時間比離上一次近 → 提早觸發。不設固定門檻，睡眠後晚觸發只要沒晚過中點照常執行。
# 只支援「分 時 * * 星期」形式（*、數字、a-b、a,b），時間一律 UTC（pm2 daemon 為 UTC）。
class LeapsIvCronGuard
  class Unsupported < StandardError; end

  FIELD_RANGES = { minute: 0..59, hour: 0..23, wday: 0..6 }.freeze
  SEARCH_DAYS  = 8 # 任何「星期」組合在 8 天內一定出現；找不到代表字串沒有任何排定時間

  def initialize(cron)
    fields = cron.to_s.split
    raise Unsupported, "需要 5 個欄位：#{cron.inspect}" unless fields.size == 5
    raise Unsupported, "只支援日、月為 *：#{cron.inspect}" unless fields[2] == "*" && fields[3] == "*"

    @minutes = parse(fields[0], :minute)
    @hours   = parse(fields[1], :hour)
    @wdays   = parse(fields[4], :wday)
  end

  def early?(now)
    (next_at(now) - now) < (now - prev_at(now))
  end

  # 嚴格晚於 now 的下一次排定時間
  def next_at(now)
    times_around(now).find { |t| t > now } || raise(Unsupported, "#{SEARCH_DAYS} 天內沒有排定時間")
  end

  # 不晚於 now 的上一次排定時間（正點那一秒算「上一次」）
  def prev_at(now)
    times_around(now).reverse.find { |t| t <= now } || raise(Unsupported, "#{SEARCH_DAYS} 天內沒有排定時間")
  end

  private

  def times_around(now)
    day0 = Time.utc(now.year, now.month, now.day)
    (-SEARCH_DAYS..SEARCH_DAYS).flat_map do |offset|
      day = day0 + offset.days
      next [] unless @wdays.include?(day.wday)

      @hours.flat_map { |h| @minutes.map { |m| day + h.hours + m.minutes } }
    end.sort
  end

  def parse(field, name)
    range  = FIELD_RANGES.fetch(name)
    values = field.split(",").flat_map { |part| parse_part(part, range) }
    raise Unsupported, "#{name} 欄位沒有任何值：#{field.inspect}" if values.empty?
    raise Unsupported, "#{name} 欄位超出範圍：#{field.inspect}" unless values.all? { |v| range.cover?(v) }

    values.uniq.sort
  end

  def parse_part(part, range)
    case part
    when "*"          then range.to_a
    when /\A\d+\z/    then [ part.to_i ]
    when /\A(\d+)-(\d+)\z/ then (::Regexp.last_match(1).to_i..::Regexp.last_match(2).to_i).to_a
    else raise Unsupported, "不支援的寫法：#{part.inspect}"
    end
  end
end
