# frozen_string_literal: true

require "open3"

class LeapsCallChainFetcher
  # 執行 bcvs 的 sidecar（一次呼叫 = 一個階段），並負責停滯判定：
  # 一個階段超過 timeout 秒沒有結束就終止整個程序群組，丟出 Stalled。
  #
  # stdout／stderr 用獨立執行緒讀：chain 的 JSON 可能超過管線緩衝區，
  # 如果等程序結束才讀，子程序會卡在寫入，反而被誤判成停滯。
  class SidecarRunner
    SCRIPT_DIR = Rails.root.join("lib/barchart_scrapers")
    SCRIPTS = { expirations: "bcvs_expirations_scraper.py", chain: "bcvs_call_chain_scraper.py" }.freeze
    KILL_GRACE_SECONDS = 2

    def initialize(command: nil)
      @command = command || method(:default_command)
    end

    def call(kind, symbol, *args, timeout:)
      argv = @command.call(kind, symbol, *args)
      Open3.popen3(*argv, chdir: Rails.root.to_s, pgroup: true) do |stdin, stdout, stderr, wait_thr|
        stdin.close
        out = reader(stdout)
        err = reader(stderr)

        unless wait_thr.join(timeout)
          terminate(wait_thr)
          # 程序已終止、管線會收到 EOF；等讀取執行緒收尾再離開 popen3 區塊，
          # 否則區塊關閉串流時執行緒還在 read，會丟 IOError。
          [ out, err ].each { |t| t.join(KILL_GRACE_SECONDS) }
          raise Stalled.new(LeapsCallChainFetcher.stage_label(kind, args.first), timeout)
        end

        parse(out.value, err.value, wait_thr.value)
      end
    end

    private

    def default_command(kind, symbol, *args)
      [ "python3", SCRIPT_DIR.join(SCRIPTS.fetch(kind)).to_s, symbol, *args ]
    end

    def reader(io)
      Thread.new do
        io.read
      rescue IOError
        ""
      end
    end

    def terminate(wait_thr)
      signal_group("TERM", wait_thr.pid)
      signal_group("KILL", wait_thr.pid) unless wait_thr.join(KILL_GRACE_SECONDS)
    end

    def signal_group(signal, pid)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def parse(stdout, stderr, status)
      return { "status" => "error", "error" => stderr.strip.first(500) } unless status.success?

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      { "status" => "error", "error" => "JSON parse error: #{e.message.first(200)}" }
    end
  end
end
