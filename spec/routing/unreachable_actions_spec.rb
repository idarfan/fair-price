# frozen_string_literal: true

require "rails_helper"

# traceroute gem 的替代品（該 gem 最後一版停在 2020-04-28，不予採用）。
#
# traceroute 報兩件事，這裡各由一半負責：
#
#   1. 路由指向不存在的 action  → Rails 內建 `bin/rails routes --unused`
#                                （已接進 bin/audit style 與 config/ci.rb）
#   2. action 沒有任何路由指到它 → 本檔案
#
# 第 2 項不只是死碼問題。Rails 把 controller 上的每一個 public method 都視為
# 可路由的 action，所以一個「不小心變成 public」的輔助方法，跟真正的 action
# 只差一條路由。實際抓到過的例子：`include Charts::TechnicalIndicators` 讓
# 模組的 6 個純計算方法全部成為 ChartsController 的 public action。
RSpec.describe "無法到達的 controller action", type: :routing do
  # 刻意保留、不視為問題的項目。每一筆都必須寫理由。
  # 用 let 而非常數：describe 內的 `X = ...` 其實定義在全域 Object 上
  # （RSpec/LeakyConstantDeclaration）。
  let(:allowed) { [] }

  # 只看定義在本專案原始碼裡的方法。Rails 內建的 public 方法
  # （ActionController::DataStreaming#send_stream 等）會被 action_methods 收進來，
  # 那不是我們的程式碼，也不該由這支測試管。
  def app_defined?(klass, method_name)
    location = klass.instance_method(method_name).source_location
    return false if location.nil?

    path = location.first
    path.start_with?(Rails.root.to_s) && !path.include?("/vendor/")
  rescue NameError
    false
  end

  def routed_actions
    Rails.application.routes.routes.filter_map { |route|
      controller = route.defaults[:controller]
      action     = route.defaults[:action]
      "#{controller}##{action}" if controller && action
    }.to_set
  end

  def unreachable_actions
    routed = routed_actions

    ApplicationController.descendants.reject(&:abstract?).flat_map { |klass|
      klass.action_methods.filter_map { |action|
        name = "#{klass.controller_path}##{action}"
        next if routed.include?(name) || allowed.include?(name)
        next unless app_defined?(klass, action)

        name
      }
    }.sort
  end

  before { Rails.application.eager_load! }

  it "沒有 controller action 是外部到不了的" do
    unreachable = unreachable_actions

    expect(unreachable).to be_empty, <<~MSG
      這些 public controller method 沒有任何路由指到它：

        #{unreachable.join("\n  ")}

      三種可能，請對症處理：
        * 它其實是輔助方法 → 改成 private（模組 include 進來的用
          `private(*SomeModule.public_instance_methods)`）
        * 它是遺留的死碼   → 刪掉 controller 與對應的 view
        * 它是刻意保留的   → 加進本檔案的 ALLOWED 並寫明理由
    MSG
  end
end
