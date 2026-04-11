#!/usr/bin/env bash
# ============================================================
#  FairPrice — 打包腳本
#  用法：bash package.sh
#  在現有機器執行，產生可複製到新 WSL2 電腦的安裝包
# ============================================================
set -euo pipefail

readonly BUNDLE_NAME="fairprice-bundle"
readonly OUTPUT_TAR="${BUNDLE_NAME}.tar.gz"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
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

# 取得 git 追蹤的檔案清單（自動排除 .gitignore 內容）
info "取得 git 追蹤檔案清單..."
mapfile -t GIT_FILES < <(git ls-files)

# 確保安裝腳本本身也包含進去（即使尚未 commit）
EXTRA_FILES=()
[[ -f "install.sh" ]] && EXTRA_FILES+=("install.sh")
[[ -f "package.sh" ]] && EXTRA_FILES+=("package.sh")

# 合併並去重
ALL_FILES=("${GIT_FILES[@]}" "${EXTRA_FILES[@]}")
# 去重（bash 4+）
IFS=$'\n' read -r -d '' -a UNIQUE_FILES < <(
  printf '%s\n' "${ALL_FILES[@]}" | sort -u && printf '\0'
) || true

info "共 ${#UNIQUE_FILES[@]} 個檔案"

# 建立暫存目錄
TMP_DIR=$(mktemp -d)
DEST="${TMP_DIR}/${BUNDLE_NAME}"
mkdir -p "$DEST"

# 複製檔案，保留目錄結構
info "複製檔案..."
for f in "${UNIQUE_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    dest_dir="${DEST}/$(dirname "$f")"
    mkdir -p "$dest_dir"
    cp "$f" "${DEST}/${f}"
  fi
done

# 確認敏感檔案不在包裡
SENSITIVE=(".env" "config/master.key" "config/credentials.yml.enc")
for s in "${SENSITIVE[@]}"; do
  if [[ -f "${DEST}/${s}" ]]; then
    rm -f "${DEST}/${s}"
    warn "已從 bundle 排除敏感檔案：${s}"
  fi
done

# 確認 install.sh 有執行權限
[[ -f "${DEST}/install.sh" ]] && chmod +x "${DEST}/install.sh"
[[ -f "${DEST}/package.sh" ]] && chmod +x "${DEST}/package.sh"

# 打包
info "打包中..."
tar -czf "$OUTPUT_TAR" -C "$TMP_DIR" "$BUNDLE_NAME"
rm -rf "$TMP_DIR"

# 結果
SIZE=$(du -sh "$OUTPUT_TAR" | cut -f1)
ok "打包完成：${BOLD}${OUTPUT_TAR}${NC}（${SIZE}）"
echo ""
echo -e "  ${BOLD}複製到新機器的方式：${NC}"
echo ""
echo -e "  ${CYAN}# SCP（在新機器執行）：${NC}"
echo -e "  scp <你的IP>:$(pwd)/${OUTPUT_TAR} ~/"
echo ""
echo -e "  ${CYAN}# 或用 USB 複製後，在新機器 WSL2 執行：${NC}"
echo -e "  tar xzf ${OUTPUT_TAR}"
echo -e "  cd ${BUNDLE_NAME}"
echo -e "  bash install.sh"
echo ""
