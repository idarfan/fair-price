# frozen_string_literal: true

# 使用者版「版本更新說明」內容 — 跟 README.md 的開發者 changelog 分開維護，
# 這裡只寫使用者看得懂、關心的功能異動，不寫內部技術細節（hook 檔名、CVE 等）。
# 新版本往陣列最前面加，RELEASE_NOTES.first 就是最新版本。
RELEASE_NOTES = [
  {
    date: "20260818",
    title: "LEAPS 選擇權工具：新增價格預估試算、欄位篩選",
    items: [
      "新增「價格預估」欄位：點擊「📈 試算」可彈出視窗，輸入預期股價、調整 IV%，即時試算該筆合約的推估價格",
      "新增欄位篩選面板：可自行勾選要顯示哪些欄位，避免表格過於擁擠（預設隱藏「被指派機率」欄）"
    ]
  }
].freeze
