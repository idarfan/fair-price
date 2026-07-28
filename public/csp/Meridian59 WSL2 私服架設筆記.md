# Meridian 59 WSL2 私服架設筆記

> 建立時間：2026-07-11
> 源碼：https://github.com/Meridian59/Meridian59 (官方 GPL 開源)
> 架構：WSL2 跑 BlakServ 私服，Windows Steam 編譯版客戶端連 `127.0.0.1:5959`（mirrored 網路直通，無需 portproxy）

## 為什麼私服最適合研究自動化

這遊戲 2012 年就 GPL 全開源了：
- Client + Server 源碼都在同一個 repo
- 沒有 BattlEye / EAC 這種反外掛
- 105/107 官方服靠 GM 肉眼巡查無人掛機，但私服你就是 GM
- 房間制地圖，尋路極簡單，物件列表 `room_contents` 都是明文 struct

官方服禁止無人值守自動打怪 (Unattended Macro)，會封號。私人服自己是服主，規則自己訂。

## WSL2 正確編譯與設定

官方沒有 `server.Dockerfile`，那是第三方寫的。官方正確方式是 `makefile.linux`

### 1. 編譯 blakserv

```bash
cd ~/Meridian59/blakserv
make -f makefile.linux -j4
# 編譯完 4.0M 執行檔會自動 cp 到 ../run/server/blakserv
ls -lh ../run/server/blakserv
```

### 2. 修改 blakserv.cfg（Windows -> Linux 路徑）

原本是 2010 年的 Windows 路徑 `loadkod\`，在 WSL2 會找不到。

已改好的版本（位於 `~/Meridian59/run/server/blakserv.cfg`）：

```ini
[Path]
Bof                  loadkod/
Memmap               memmap/
Rsc                  rsc/
Rooms                ../../resource/rooms/
Motd                 ./
Channel              channel/
LoadSave             savegame/
Forms                ./
Kodbase              ../../kod
PackageFile          ./

[Socket]
Port                 5959
MaintenancePort      5960

[Channel]
DebugDisk            Yes
ErrorDisk            Yes
LogDisk              Yes

[Constants]
Enabled   Yes
Filename  ../../kod/include/blakston.khd

[Advertise]
...
```

重點：Windows `\` 全部改 `/`，補上 `[Socket]` 的 Port，**注意官方 config_table 沒有 `LockPort`，正版 key 是 `MaintenancePort`**，寫錯就會報 `LoadConfig can't match value ... (16)`。否則 Linux 版沒 GUI 可填。

### 2.1 編譯依賴與順序（重點坑位）

```bash
sudo apt-get install -y flex bison
cd ~/Meridian59/blakcomp && make -f makefile.linux
cd ../kod && make -f makefile.linux   # 注意不能 -j4，必須單線程，否則 util.kod 還沒編就去編 parlia.kod 會報 Can't find superclass UtilityFunctions
# 成功後 run/server/loadkod/ 應有 1231 bof，rsc/ 1137 rsc
```

之前直接 `./blakserv` 出現 `can't match value blakserv.cfg (16)` 就是第 16 行 `LockPort` 寫錯。

### 2.2 啟動排錯

```bash
cd ~/Meridian59/run/server
rm -rf memmap/* channel/*
./blakserv
# 若 loadkod/ 或 rsc/ 空的會噴 1.2MB error.log：LoadKodbaseClass can't find class id ...
# 正常應 LISTEN 0.0.0.0:5959 5959 口
ss -tlnp | grep 5959
# EXIT:124 表示被 timeout 殺掉，不是錯誤，是正常卡住跑著
```

已驗證：2026-07-11 在 WSL2 成功跑起，PID 1136837 / 1138120，5959/5960 LISTEN，
Windows 因 mirrored 模式連 127.0.0.1:5959 直通。

## Steam 客戶端直連 WSL2 私服

WSL2 已改好 `mirrored` 模式，不用 portproxy

### 一鍵啟動

已在 Steam 目錄建立：

**`C:\Program Files (x86)\Steam\steamapps\common\Meridian 59\Connect-WSL2-Private.bat`**

```bat
Meridian.exe /H:127.0.0.1 /P:5959 /U:Chris.Kirmse /W:11111111
```

`/H:` / `/P:` 是官方直連參數，跳過105/107列表，一開就連WSL2

### 首次建自己帳號（空服只有內建2個開發者帳號）

1. 用 `Chris.Kirmse / 11111111` 登入選 Administration
2. `create account admin idarfan password`
3. `create admin 5` (ID看上一行回傳)
4. `save game`

存完後 `savegame/accounts.*` 才會持久化

官方 Linux 版 `osd_linux.c` 註明 `no console admin interface`，所以WSL2不能本地打指令創帳號，必須Windows連上後進Administration模式創

### 3. 啟動

```bash
cd ~/Meridian59/run/server
./blakserv
# 監聽 5959 登入 5960 遊戲
ss -tlnp | grep 5959
```

Windows 防火牆若擋，放行 5959/5960。

### 4. 創建帳號（在 blakserv console 裡打）

```
create account admin 你的帳號 你的密碼
# 回傳 ACCOUNT 4 之類
create admin 4
# save game 一定要
```

### 5. Windows 客戶端連私服

Steam 上鎖服列表的那個版本連不了私。要用開源編譯版 Client：

官方 README：Build 後在 `run/localclient/` 有 `meridian.exe`
啟動參數：

```
meridian.exe /U:你的帳號 /W:你的密碼 /H:127.0.0.1 /P:5959
```

或 F10 -> Add Server -> 127.0.0.1:5959

因為 WSL2 是 `networkingMode=mirrored`，Windows 連 `localhost` = 連 WSL2。

## 自動打怪可行性評估：9/10

### 三種路線

| 路線 | 原理 | 穩定度 | 風險 |
|---|---|---|---|
| A 像素辨識 | Python + PyAutoGUI/OpenCV 截圖找血條 | 低 | 低 |
| B 記憶體掛 | 讀客戶端記憶體物件列表 | 中 | 中 |
| C 源碼修改 (推薦) | Fork 官方 Client，在 room.c/object.c 加狀態機 | 極高 | 最低 |

私人服推薦 **C + 伺服器端 Blakod 傭兵**

### 私服正規做法：Blakod 傭兵 AI

Meridian 私服邏輯是 **Blakod** 腳本語言，怪物 AI 都在 `kod/` 目錄。

不是寫外部外掛，而是直接在伺服器寫一個 NPC：

```
Idle -> 掃描 room_contents -> 過濾可攻擊
     -> 距離排序選目標
     -> 官方尋路靠近
     -> attack
     -> 血量<60% heal/喝水
     -> 死亡 -> loot
     -> 沒怪 -> 跟隨主人
     -> 隨機 300-800ms 延遲
```

檔案位置：打包圍相關 `kod/include/` 和 `kod/` 下 monster 定義是最好的範本，複製改成跟隨玩家即可。社群叫 Mercenary Mod。

### 安全/反掛機

自己私人服用 Blakod 傭兵 = 官方允許的 Mod，不是外掛。
若未來要放上公開私服，多數規則是禁「無人值守」，需加：
- 隨機延遲、人類化停頓
- 關鍵字監聽有人/GM密你自動暫停
- 自動重連

## 相關檔案

- `~/Meridian59/run/server/blakserv` (編好的 4.0M 執行檔)
- `~/Meridian59/run/server/blakserv.cfg` (已改 Linux 版)
- `~/Meridian59/README` (官方建置說明)
- `~/Meridian59/kod/` (Blakod 遊戲邏輯)
- `~/Meridian59/clientd3d/` -> `room.c` / `object.c` (客戶端物件列表)

## 下一步 TODO

- [x] WSL2 blakserv 編譯與配置修復（LockPort->MaintenancePort, \ -> /）
- [x] Steam 客戶端直連 bat (Connect-WSL2-Private.bat)
- [x] 空服建帳號流程驗證
- [ ] 在 WSL2 調好傭兵 .kod
- [ ] Windows 編譯版客戶端自動改 `servers.ini`
- [ ] 要不要加自動尋路熱點刷怪房間列表
