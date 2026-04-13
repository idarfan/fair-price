#!/usr/bin/env bash
# ============================================================
#  FairPrice — 打包腳本
#  用法：bash package.sh
#  執行後將 ~/fairprice-installer 複製到隨身碟即可
# ============================================================
set -euo pipefail

readonly OUTPUT_DIR="${HOME}/fairprice-installer"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

# 確認在 app 根目錄
if [[ ! -f "Gemfile" ]]; then
  echo "請在 fairprice app 根目錄執行此腳本"
  exit 1
fi

echo -e "${BOLD}FairPrice 打包工具${NC}"
echo ""

# 若輸出目錄已存在則先刪除
if [[ -d "$OUTPUT_DIR" ]]; then
  warn "舊的安裝目錄已存在，清除中..."
  rm -rf "$OUTPUT_DIR"
fi
mkdir -p "$OUTPUT_DIR"

# 取得 git 追蹤的檔案清單（自動排除 .gitignore 內容）
info "取得 git 追蹤檔案清單..."
mapfile -t GIT_FILES < <(git ls-files)

# 額外補上安裝腳本（即使尚未 commit）
EXTRA_FILES=()
[[ -f "install.sh" ]] && EXTRA_FILES+=("install.sh")
[[ -f "package.sh" ]] && EXTRA_FILES+=("package.sh")

# 合併去重
IFS=$'\n' read -r -d '' -a ALL_FILES < <(
  printf '%s\n' "${GIT_FILES[@]}" "${EXTRA_FILES[@]}" | sort -u && printf '\0'
) || true

info "複製 ${#ALL_FILES[@]} 個檔案..."
for f in "${ALL_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    dest_dir="${OUTPUT_DIR}/$(dirname "$f")"
    mkdir -p "$dest_dir"
    cp "$f" "${OUTPUT_DIR}/${f}"
  fi
done

# 確保敏感檔案與不需要的設定不在輸出目錄
for s in ".env" "config/master.key" "config/credentials.yml.enc" ".github/dependabot.yml"; do
  if [[ -f "${OUTPUT_DIR}/${s}" ]]; then
    rm -f "${OUTPUT_DIR}/${s}"
    warn "已排除敏感檔案：${s}"
  fi
done

# 確保所有 .sh 可執行
find "${OUTPUT_DIR}" -name "*.sh" -exec chmod +x {} \;

# 結果
SIZE=$(du -sh "$OUTPUT_DIR" | cut -f1)
echo ""
ok "安裝目錄已建立：${BOLD}${OUTPUT_DIR}${NC}（${SIZE}）"
echo ""
echo -e "  ${BOLD}下一步：將此目錄複製到隨身碟${NC}"
echo ""
echo -e "  ${CYAN}# 複製到隨身碟（範例，依實際掛載點調整）${NC}"
echo -e "  cp -r ${OUTPUT_DIR} /mnt/<隨身碟路徑>/"
echo ""
echo -e "  ${CYAN}# 在新電腦上（WSL2 終端機）：${NC}"
echo -e "  cp -r /mnt/<隨身碟路徑>/fairprice-installer ~/"
echo -e "  cd ~/fairprice-installer"
echo -e "  bash install.sh"
echo ""
