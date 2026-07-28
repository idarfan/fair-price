#!/bin/bash
# 產生一個 .bat 檔讓使用者在 Windows 管理員 CMD 執行
cat > /tmp/allow_wsl2_port.bat << 'EOF'
@echo off
echo 新增 Windows 防火牆規則，允許從 Windows Chrome 連線到 WSL2 port 8765...
netsh advfirewall firewall add rule name="WSL2 HTTP 8765" protocol=TCP dir=in localport=8765 action=allow
echo 完成！請關閉此視窗後，回到 Claude Code 重試截圖。
pause
EOF
echo "已產生 /tmp/allow_wsl2_port.bat"
echo ""
echo "請在 Windows 執行（可以用 WSL2 路徑開啟）："
echo "  \\\\wsl.localhost\\Ubuntu\\tmp\\allow_wsl2_port.bat"
echo ""
echo "或者直接在 Windows 管理員 CMD 執行："
echo "  netsh advfirewall firewall add rule name=\"WSL2 HTTP 8765\" protocol=TCP dir=in localport=8765 action=allow"
