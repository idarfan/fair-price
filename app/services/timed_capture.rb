# frozen_string_literal: true

require "open3"

# Open3.capture3 加上時限。capture3 本身沒有逾時：子程序卡住（例如爬蟲對 CDP 的
# websocket 一直等不到回應）呼叫端就跟著永遠卡住。
#
# 子程序開在自己的 process group，逾時時整組一起砍——爬蟲若衍生了孫程序，
# 只砍子程序會留下孤兒繼續佔著 pipe。先送 TERM 給它機會收尾，寬限期後再 KILL。
module TimedCapture
  Result = Data.define(:stdout, :stderr, :status, :timed_out)

  DEFAULT_KILL_GRACE_S = 5

  def self.call(*cmd, timeout:, kill_grace: DEFAULT_KILL_GRACE_S, **opts)
    Open3.popen3(*cmd, pgroup: true, **opts) do |stdin, stdout, stderr, wait|
      stdin.close
      # 兩條 pipe 都要邊跑邊讀，否則輸出一大子程序就卡在 write，看起來像逾時。
      out = Thread.new { stdout.read }
      err = Thread.new { stderr.read }

      timed_out = wait.join(timeout).nil?
      terminate_group(wait, kill_grace) if timed_out

      Result.new(stdout: out.value, stderr: err.value, status: wait.value, timed_out: timed_out)
    end
  end

  # 寬限期後不管子程序走了沒，一律對整組補一發 KILL：子程序可能已經收 TERM 結束，
  # 但不理 TERM 的孫程序還握著 stdout，讀 pipe 的 thread 就永遠等不到 EOF。
  def self.terminate_group(wait, kill_grace)
    signal_group("TERM", wait.pid)
    wait.join(kill_grace)
    signal_group("KILL", wait.pid)
    wait.join
  end
  private_class_method :terminate_group

  # 子程序先自己結束、孫程序還在的話 group 依然存在；整組都沒了才會 ESRCH。
  def self.signal_group(signal, pgid)
    Process.kill(signal, -pgid)
  rescue Errno::ESRCH
    nil
  end
  private_class_method :signal_group
end
