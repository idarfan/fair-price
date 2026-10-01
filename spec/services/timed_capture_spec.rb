# frozen_string_literal: true

require "rails_helper"

# 用真的子程序測：逾時判斷與「真的有砍掉」都是行程層級的行為，stub 掉就什麼都沒測到。
RSpec.describe TimedCapture do
  let(:ruby) { RbConfig.ruby }

  it "時限內結束：回傳 stdout／stderr／exit status" do
    result = described_class.call(ruby, "-e", "puts 'out'; warn 'err'; exit 3", timeout: 10)

    expect(result.timed_out).to be(false)
    expect(result.stdout).to eq("out\n")
    expect(result.stderr).to eq("err\n")
    expect(result.status.exitstatus).to eq(3)
  end

  it "超過時限：回 timed_out，並在時限附近返回而不是等子程序自己結束" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result  = described_class.call(ruby, "-e", "sleep 30", timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(result.timed_out).to be(true)
    expect(elapsed).to be < 10
  end

  it "逾時時連子程序衍生的孫程序一起砍掉（整個 process group）" do
    pid_file = Rails.root.join("tmp", "timed_capture_child_#{SecureRandom.hex(4)}.pid")
    script = "pid = spawn('sleep', '30'); File.write('#{pid_file}', pid); sleep 30"

    result = described_class.call(ruby, "-e", script, timeout: 2)

    expect(result.timed_out).to be(true)
    grandchild = File.read(pid_file).to_i
    expect { Process.kill(0, grandchild) }.to raise_error(Errno::ESRCH)
  ensure
    FileUtils.rm_f(pid_file) if pid_file
  end

  it "不理會 TERM 的子程序，寬限期後用 KILL 收掉" do
    script = "trap('TERM') {}; sleep 30"

    result = described_class.call(ruby, "-e", script, timeout: 1, kill_grace: 1)

    expect(result.timed_out).to be(true)
    expect(result.status).not_to be_nil
  end

  it "輸出很大時不會因為 pipe 塞滿而卡住" do
    result = described_class.call(ruby, "-e", "STDOUT.write('x' * 1_000_000)", timeout: 10)

    expect(result.timed_out).to be(false)
    expect(result.stdout.bytesize).to eq(1_000_000)
  end
end
