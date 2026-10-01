# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # 本 Rails 程序的識別碼，給「job 還在跑」類的登記用（排程鎖、進行中登記）。
  # Async adapter 的 job 跑在 Rails 程序裡，server 重啟時 job 會被砍掉、登記沒人清；
  # 登記記下這個值，程序換了，舊登記直接作廢。
  PROCESS_TOKEN = "#{Process.pid}-#{SecureRandom.hex(4)}".freeze

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked
  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
