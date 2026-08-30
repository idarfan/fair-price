# frozen_string_literal: true

require "rails_helper"

# 稽核 H-3：Phlex 元件的內嵌 JavaScript 搬到 app/frontend/behaviors/ 之後，
# 元件與模組之間的連結只剩下一個字串（data-behavior）。這支測試把那個連結釘住——
# 打錯字或忘記註冊都會在測試階段就被抓到，而不是等到使用者按下去沒反應。
RSpec.describe "行為模組註冊表", type: :model do
  # 掛載標記可能出現在 Phlex 元件，也可能直接寫在 layout / view 裡
  # （例如換頁進度條、更新說明彈窗這種全站層級的行為）。
  # 用 let 而非 describe 內的常數：describe 區塊裡的 `X = ...` 其實定義在
  # 全域 Object 上，兩支 spec 撞名時會靜默取到別人的值（RSpec/LeakyConstantDeclaration）。
  let(:marker_globs) do
    [
      Rails.root.join("app/components/**/*.rb"),
      Rails.root.join("app/views/**/*.erb")
    ]
  end
  let(:components_glob) { Rails.root.join("app/components/**/*.rb") }
  let(:behaviors_dir)   { Rails.root.join("app/frontend/behaviors") }
  let(:registry_file)   { Rails.root.join("app/frontend/entrypoints/behaviors.ts") }

  # 元件裡實際輸出的 data-behavior 值
  # Phlex 寫成 `behavior: "x"`，ERB 寫成 `data-behavior="x"`
  def markers_in_components
    marker_globs.flat_map { |g| Dir[g] }.flat_map { |f|
      src = File.read(f)
      src.scan(/behavior:\s*"([a-z0-9-]+)"/).flatten + src.scan(/data-behavior="([a-z0-9-]+)"/).flatten
    }.uniq.sort
  end

  # entrypoints/behaviors.ts 的 REGISTRY 註冊了哪些名稱 → 對應哪個模組
  def registry
    File.read(registry_file)
        .scan(%r{"([a-z0-9-]+)":\s*\(\)\s*=>\s*import\("\.\./behaviors/([A-Za-z0-9_]+)"\)})
        .to_h
  end

  it "每個元件用到的 data-behavior 都有註冊" do
    unregistered = markers_in_components - registry.keys

    expect(unregistered).to be_empty,
      "這些 data-behavior 沒有註冊到 entrypoints/behaviors.ts：#{unregistered.join(', ')}"
  end

  it "每個註冊的 behavior 都有對應的模組檔案" do
    missing = registry.filter_map do |name, mod|
      "#{name} → #{mod}" unless %w[js ts].any? { |ext| behaviors_dir.join("#{mod}.#{ext}").exist? }
    end

    expect(missing).to be_empty, "註冊了但找不到模組檔：#{missing.join(', ')}"
  end

  it "每個模組都 export 了 init" do
    without_init = Dir[behaviors_dir.join("*.{js,ts}")].reject do |f|
      File.read(f).match?(/export\s+function\s+init\b/)
    end

    expect(without_init).to be_empty,
      "這些模組沒有 export function init：#{without_init.map { |f| File.basename(f) }.join(', ')}"
  end

  it "沒有註冊了卻沒被任何元件使用的孤兒" do
    orphans = registry.keys - markers_in_components

    expect(orphans).to be_empty, "註冊了但沒有元件使用：#{orphans.join(', ')}"
  end

  # 搬遷的重點就是把 JavaScript 移出 Ruby 字串。這條防止有人又把它加回來。
  it "已搬遷的元件不再內嵌 JavaScript" do
    migrated = Dir[components_glob].select { |f| File.read(f).include?("data: { behavior:") }
    expect(migrated).not_to be_empty, "找不到任何已搬遷的元件，測試本身可能失效了"

    still_inline = migrated.select do |f|
      src = File.read(f)
      src.match?(/<<[-~]'?JS'?/) || src.match?(/raw <<[-~].*\.html_safe/m) && src.match?(/function\s*\(|addEventListener/)
    end

    expect(still_inline).to be_empty,
      "這些元件仍有內嵌 JavaScript：#{still_inline.map { |f| f.sub(Rails.root.to_s + '/', '') }.join(', ')}"
  end
end
