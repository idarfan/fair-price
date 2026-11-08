# frozen_string_literal: true

require "rails_helper"

# leaps-iv-environment P7.1：pm2（croner）提早觸發的判斷。時間一律 UTC。
# 2026-11-07 是週六；11/07 實際觸發序列 05:15:56、05:57:30、05:59:50、06:00:00（pm2.log）。
RSpec.describe LeapsIvCronGuard do
  subject(:guard) { described_class.new("0 6 * * 2-6") }

  def utc(str) = Time.utc(*str.scan(/\d+/).map(&:to_i))

  describe "#early?" do
    {
      "2026-11-07 05:15:56" => true,  # 提早 44 分
      "2026-11-07 05:57:30" => true,  # 提早 2.5 分
      "2026-11-07 05:59:50" => true,  # 提早 10 秒
      "2026-11-10 01:48:00" => true,  # 週六→週二 72 小時間隔、提早 4.2 小時
      "2026-11-07 06:00:00" => false, # 正點
      "2026-11-07 06:07:00" => false, # 正點後
      "2026-11-07 09:30:00" => false, # 睡眠後晚觸發
      "2026-11-08 10:00:00" => false  # 週日手動 pm2 restart：離上一次（週六）比下一次（週二）近
    }.each do |at, expected|
      it "#{at} UTC → #{expected ? '略過' : '執行'}" do
        expect(guard.early?(utc(at))).to eq(expected)
      end
    end
  end

  describe "#next_at／#prev_at" do
    it "週六 05:15:56 的上一次是週五 06:00、下一次是週六 06:00" do
      now = utc("2026-11-07 05:15:56")
      expect(guard.prev_at(now)).to eq(utc("2026-11-06 06:00:00"))
      expect(guard.next_at(now)).to eq(utc("2026-11-07 06:00:00"))
    end

    it "週日的下一次跳過週日、週一，是週二 06:00" do
      expect(guard.next_at(utc("2026-11-08 10:00:00"))).to eq(utc("2026-11-10 06:00:00"))
    end

    it "支援逗號與多個時、分" do
      g = described_class.new("0,30 13-20 * * 1-5")
      expect(g.next_at(utc("2026-11-06 14:29:57"))).to eq(utc("2026-11-06 14:30:00"))
      expect(g.prev_at(utc("2026-11-06 14:29:57"))).to eq(utc("2026-11-06 14:00:00"))
    end
  end

  describe "不支援的字串" do
    [ "*/30 13-20 * * 1-5", "0 6 1 * *", "0 6 * 11 *", "0 6 * *", "x 6 * * *" ].each do |cron|
      it "#{cron.inspect} → Unsupported" do
        expect { described_class.new(cron) }.to raise_error(LeapsIvCronGuard::Unsupported)
      end
    end
  end
end
