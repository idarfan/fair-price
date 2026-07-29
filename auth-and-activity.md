# 規格:Google OAuth + TOTP 登入、帳戶管理、活躍度追蹤

## 執行狀態表

| 階段 | 說明 | 狀態 | 驗證方式 |
|---|---|---|---|
| 0 | 環境準備(兩處環境變數,先做完才可繼續) | 未開始 | WSL2 本機與 tunnel 正式環境**各自**執行 `ENV['GOOGLE_CLIENT_ID'].present? && ENV['ADMIN_EMAILS'] == 'mr.idarfan@gmail.com'`,兩邊皆 true 才算過 |
| 1 | Schema:User + UserActivity | 未開始 | migration 通過,欄位齊全(見階段內容) |
| 2 | Google 開放註冊(pending) | 未開始 | 任意 email 首登建 User(pending);disabled 導 `/account_disabled`;ADMIN_EMAILS 自動 enabled+admin |
| 3 | TOTP 強制設定 | 未開始 | 未設定前任何非 `/two_factor/*` 路由導回 setup;正確碼寫入 totp_enabled,錯誤碼不寫 |
| 4 | TOTP 登入挑戰 | 未開始 | 未過 totp_verified 擋所有受保護路由;連錯 5 次鎖 5 分鐘 |
| 5 | 備用碼 | 未開始 | 用過即失效;重新產生使舊碼全失效 |
| 6 | 帳號安全頁 | 未開始 | 可重產備用碼、可登出所有裝置(session_version 機制) |
| 7 | 帳戶管理頁(Admin) | 未開始 | 非 admin 擋 `/admin/users`;核准/停用即時生效(停用連現有 session 一併踢除) |
| 8 | 頁面停留時間追蹤 | 未開始 | beacon 觸發寫入 duration_ms;心跳更新同 token 不重複建列 |
| 9 | 指令使用追蹤 | 未開始 | 觸發指定功能建立 command 紀錄,action_name 正確 |
| 10 | Admin 頁串接統計 | 未開始 | `/admin/users` 顯示累積停留時間/常用指令/最後活動時間,與 DB 一致 |
| 11 | End-to-end 驗證 | 未開始 | Playwright 全流程截圖(見階段 11) |

> 接續 session 只讀本表 + 進行中階段。

> **強制順序**:階段 0(兩處環境變數設定並驗證通過)必須先完成,才可開始任何其他階段。未看到階段 0 驗證通過的證據前,不得動 schema、controller 或任何程式碼。

---

## 決策摘要

- 開放註冊,不設白名單;新帳號預設 `pending`,需 admin 於 `/admin/users` 核准才能用主功能。
- `ADMIN_EMAILS=mr.idarfan@gmail.com` 首登自動 `enabled + admin`,略過審核。
- 雙因子(Google 登入 + TOTP)皆必要,不可跳過;審核狀態與 TOTP 設定各自獨立判斷。
- TOTP secret、備用碼一律 `encrypts` 加密存放。
- 停留時間不存 cookie:cookie(既有 session)只用來認人,時間數據由前端 JS 量測、`sendBeacon` 送後端寫 DB。
- TOTP issuer 名稱固定為 `FairPrice-Ohmy`,QR code label 不帶 email,手機 Authenticator app 裡單純顯示 FairPrice-Ohmy。若同一支手機未來要裝多個帳號需自行分辨,目前設計是單一使用者情境優先。

---

## 待辦事項(阻塞性,須先解決才能繼續驗證任何階段)

### 1. `redirect_uri_mismatch`(Google 登入直接被擋)
- 現象:`https://fairprice-ohmy.com/login` 點「使用 Google 登入」後,Google 回報 `錯誤 400:redirect_uri_mismatch`
- 疑似原因:Cloudflare Tunnel 把外部 https 請求轉成內部 http 送進 Rails,OmniAuth 沒有正確判斷原始請求是 https,組出來的 callback URL 變成 `http://fairprice-ohmy.com/auth/google_oauth2/callback`,跟 GCP Console 登記的 `https://fairprice-ohmy.com/auth/google_oauth2/callback` 對不上
- 修法:
  1. `config/initializers/omniauth.rb` 明確指定 `OmniAuth.config.full_host = "https://fairprice-ohmy.com"`,不要依賴 proxy 標頭判斷
  2. 確認 Rails 有正確信任 `X-Forwarded-Proto` 標頭(若走 `config.force_ssl` 或反向 proxy middleware 相關設定)
- **驗證**:先看 Google 錯誤頁「錯誤詳細資料」裡實際收到的 redirect_uri 是什麼,確認是 http 而非 https 這個假設成立,再修;修完後實際跑一次 `https://fairprice-ohmy.com/login` 完整 Google 登入,不噴 400

### 2. 正式環境洩漏 Rails 除錯頁(資訊安全問題,優先度高)
- 現象:打錯路徑(如 `/admin`)會看到完整 `Routing Error` 頁,含 `Rails.root` 路徑、`config/routes.rb:9` 原始碼位置、Application/Framework/Full Trace 連結
- 這代表正式環境目前在用 development 模式的詳細錯誤頁,對外公開網域上任何人打錯路徑都能看到伺服器檔案結構
- 修法:確認 `config/environments/production.rb` 內 `config.consider_all_requests_local = false`;確認 pm2 啟動該 process 時,環境變數 `RAILS_ENV=production` 真的有生效(不是預設落到 development)
- **驗證**:故意打一個不存在的路徑(如 `/this-route-does-not-exist`),應顯示一般 404 頁面,不含任何路徑/程式碼細節或 trace 連結

### 3. Admin 路徑打錯
- 正確路徑是 `/admin/users`,不是 `/admin`(單純備註,非程式問題)

以上三項修完後,才能真正跑階段 2-7 的完整登入 → 核准流程驗證。

---

## 階段 0:環境準備(先做,做完才可繼續)

- Gemfile:`omniauth-google-oauth2`、`omniauth-rails_csrf_protection`、`rotp`、`rqrcode`
- GCP OAuth Client(Web),redirect URI:`https://fairprice-ohmy.com/auth/google_oauth2/callback`
- ENV(**兩處都要設,缺一不可**):
  1. WSL2 本機開發環境(`.env` 或 `rails credentials`)
  2. tunnel 對外服務所在的正式執行環境
  - 變數:`GOOGLE_CLIENT_ID`、`GOOGLE_CLIENT_SECRET`、`ADMIN_EMAILS=mr.idarfan@gmail.com`
- 完成後於兩處環境**各自**執行驗證指令,兩邊結果都要回報,不可只驗一邊當作全部完成:
  `bin/rails runner "puts ENV['GOOGLE_CLIENT_ID'].present? && ENV['ADMIN_EMAILS'] == 'mr.idarfan@gmail.com'"`

---

## 階段 1:Schema

```ruby
create_table :users do |t|
  t.string :email, null: false, index: { unique: true }
  t.string :google_uid, null: false, index: { unique: true }
  t.string :totp_secret_ciphertext
  t.boolean :totp_enabled, default: false, null: false
  t.text :backup_codes_ciphertext
  t.integer :status, default: 0, null: false # pending/enabled/disabled
  t.boolean :admin, default: false, null: false
  t.integer :session_version, default: 0, null: false
  t.datetime :approved_at
  t.timestamps
end

create_table :user_activities do |t|
  t.references :user, null: false, foreign_key: true
  t.integer :kind, null: false # page_view/command
  t.string :path
  t.string :action_name
  t.string :activity_token
  t.datetime :started_at, null: false
  t.datetime :ended_at
  t.integer :duration_ms
  t.jsonb :metadata, default: {}
  t.timestamps
end
add_index :user_activities, [:user_id, :kind, :started_at]
```

- `User`:`encrypts :totp_secret`、`encrypts :backup_codes`;`enum status: {pending:0, enabled:1, disabled:2}`;不存密碼
- `UserActivity`:`enum kind: {page_view:0, command:1}`

---

## 階段 2:Google 開放註冊

> **與階段 3 的依賴**:本階段只建立登入路由(`/login`、`/auth/google_oauth2/callback`、`/logout`),**不加全域強制登入的 before_action**。現有頁面(root/momentum/options/leaps 等)維持可直接訪問。全站「未登入/未過 TOTP 一律導回」的守門邏輯要等 `/two_factor/setup`、`/two_factor/challenge` 頁面都寫完(階段 3、4 做完)才能一起加上,否則會把使用者導向一個還不存在的頁面,整個 app 鎖死。階段 2、3、4 建議同一輪做完,不要在只完成階段 2 的狀態下收工。

`SessionsController#google_callback`:
1. 取 omniauth email
2. `find_or_create_by(google_uid:)`;新建時 email ∈ `ADMIN_EMAILS` → `enabled+admin+approved_at`,否則 `pending`
3. 寫 `session[:user_id]`、`session[:totp_verified]=false`
4. `disabled` → `/account_disabled`
5. `totp_enabled? false` → `/two_factor/setup`;`true` → `/two_factor/challenge`
6. 全域守門:TOTP 過關後 `pending` → `/pending_approval`;`disabled` → `/account_disabled`

---

## 階段 3:TOTP 強制設定

> **全域強制登入的 before_action 在此階段(與階段 4 一起)才加上**,見階段 2 說明。

- 全域 `before_action`:`totp_enabled==false` 時,非 `/two_factor/*`、非 `/logout` 一律導回 setup
- `/two_factor/setup` GET:產生 secret 暫存 session,用 `ROTP::TOTP.new(secret, issuer: "FairPrice-Ohmy").provisioning_uri("FairPrice-Ohmy")` 產生 QR code(label 不帶 email,手機上單純顯示 FairPrice-Ohmy)+ 顯示手動輸入用金鑰
- POST:驗證通過 → 寫入 secret、`totp_enabled=true`、產生 10 組備用碼 → 導 `/two_factor/backup_codes`;失敗不寫入
- `/two_factor/backup_codes`:一次性顯示,離開後只能查「已用/未用」狀態

---

## 階段 4:TOTP 登入挑戰

- `/two_factor/challenge` POST:6 碼(`ROTP::TOTP#verify`,±1 window)或備用碼(用後標記失效)通過 → `session[:totp_verified]=true`
- 連錯 5 次鎖該 session 5 分鐘,回應標示解鎖時間

---

## 階段 5:備用碼

- 一次性使用,`used_at` 非空即失效
- 帳號安全頁「重新產生」→ 舊 10 組全作廢,產新 10 組並重新一次性顯示

---

## 階段 6:帳號安全頁

- `/settings/security`:TOTP 狀態、重產備用碼、「登出所有裝置」(`session_version` 遞增使舊 session 失效)
- 使用者選單新增入口,不進主功能 sidebar

---

## 階段 7:帳戶管理頁(Admin)

- `/admin/users`,僅 `admin?` 可見(非 admin 404,不用 403)
- 列表:email、註冊時間、status、TOTP 狀態、最後登入、操作
- 操作:核准(pending→enabled,寫 approved_at)、停用(→disabled)、重新啟用(→enabled)
- 停用同時遞增該 user `session_version`,使其現有 session 立即失效
- 不做刪除使用者
- 使用者選單「帳戶管理」入口僅 `admin?` 顯示

---

## 階段 8:頁面停留時間追蹤

- 共用 layout JS:載入時記 `started_at` + 產生 `activity_token`;`visibilitychange`/`pagehide` 時算 `duration_ms`,`sendBeacon` 送 `/track/page_view`
- 長時間停留同頁:每 5 分鐘用同 token 補送心跳,防資料因崩潰遺失
- 後端:未登入請求忽略;`activity_token` 存在則 upsert,不重複建列

---

## 階段 9:指令使用追蹤

- 涵蓋:LEAPS 篩選、PMCC/bpus/bcvs 試算、PDF/PNG 匯出、IV Skew 重整
- 按鈕加 `data-track-action`,共用 click handler fire-and-forget POST `/track/command`
- `metadata` 僅存操作摘要(如 ticker、匯出格式),不存整包表單
- 未登入請求忽略

---

## 階段 10:Admin 頁串接統計

- `/admin/users` 每列加:累積停留時間、近 7 天常用指令 Top3、最後活動時間
- `/admin/users/:id` 明細:頁面瀏覽清單(路徑+時長)、指令紀錄(時間+action_name+metadata)

---

## 階段 11:End-to-end 驗證

Playwright 全程截圖存證(URL + 關鍵 DOM 值,不可只憑測試通過數量結案):
1. `/login` → Google 登入(一般 email)
2. TOTP 設定 → 備用碼顯示
3. 導向 `/pending_approval`,確認擋主頁
4. Admin 登入,`/admin/users` 核准該帳號
5. 該帳號重新整理/登入 → 進主頁
6. 瀏覽 3 頁 + 觸發 2 個指令
7. Admin 頁確認累積時間/常用指令與實際操作一致
8. Admin 停用該帳號 → 其現有 session 立即失效,導向 `/account_disabled`
