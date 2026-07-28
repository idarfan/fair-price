#!/bin/bash
# 產生 Windows 管理員 CMD 指令，複製貼上執行
echo "=== 請在 Windows 管理員 CMD 執行以下兩行 ==="
echo ""
echo "netsh interface portproxy add v4tov4 listenport=8765 listenaddress=127.0.0.1 connectport=8765 connectaddress=192.168.1.165"
echo ""
echo "netsh advfirewall firewall add rule name=\"WSL2 portproxy 8765\" protocol=TCP dir=in localport=8765 action=allow"
echo ""
echo "執行後回 Claude Code 繼續"
