/**
 * RKLB Options Flow 分析工具
 * 用途：讀取 Barchart Options Flow 下載的 CSV，依到期日排序統計各 Strike 的交易筆數、總張數、總權利金
 *
 * 使用方法：
 *   1. 從 Barchart Options Flow 頁面下載 CSV（右上角 download 按鈕）
 *   2. 把 CSV 檔案路徑填入下方 CSV_FILE_PATH（或用command line參數帶入）
 *   3. 在終端機執行：node analyze-options-flow.js [CSV路徑]
 *      例如：node analyze-options-flow.js rklb-options-flow-06-17-2026.csv
 *
 * 環境需求：只需要 Node.js（無需安裝任何 npm 套件）
 */

const fs = require('fs');
const path = require('path');

// ===== 可調整參數 =====
const TOP_N = 10;              // 顯示前幾筆
const DEFAULT_CSV_FILE = 'options-flow.csv'; // 沒帶參數時預設讀取的檔名

// ===== 主程式 =====

function main() {
  const csvPath = process.argv[2] || DEFAULT_CSV_FILE;

  if (!fs.existsSync(csvPath)) {
    console.error(`找不到檔案：${csvPath}`);
    console.error(`用法：node ${path.basename(__filename)} <CSV檔案路徑>`);
    process.exit(1);
  }

  const csvText = fs.readFileSync(csvPath, 'utf8');
  const rows = parseCSV(csvText).filter(r => r.Type === 'Call' || r.Type === 'Put');

  if (rows.length === 0) {
    console.error('CSV 中找不到有效的 Call/Put 資料，請確認檔案格式是否為 Barchart Options Flow 下載格式');
    process.exit(1);
  }

  const symbol = rows[0].Symbol || '(未知標的)';
  const groups = groupByContract(rows);
  const groupArr = Object.values(groups).sort((a, b) => new Date(a.expires) - new Date(b.expires));

  printSummary(symbol, rows);
  printTopSingleTrades(rows);
  printTopByExpiry(groupArr);
  printTopByPremiumOverall(groupArr);
  printExpiryList(groupArr);
}

// ---- CSV 解析（簡易版，支援含逗號的雙引號欄位） ----
function parseCSV(text) {
  const lines = text.trim().split('\n');
  if (lines.length < 2) return [];
  const headers = parseLine(lines[0]);
  const rows = [];
  for (let i = 1; i < lines.length; i++) {
    const values = parseLine(lines[i]);
    if (values.length !== headers.length) continue; // 跳過格式不符的行（例如檔尾的下載說明文字）
    const row = {};
    headers.forEach((h, idx) => row[h] = values[idx]);
    rows.push(row);
  }
  return rows;
}

function parseLine(line) {
  const result = [];
  let cur = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') {
      inQuotes = !inQuotes;
    } else if (c === ',' && !inQuotes) {
      result.push(cur);
      cur = '';
    } else {
      cur += c;
    }
  }
  result.push(cur);
  return result;
}

// ---- 統計邏輯 ----
function groupByContract(rows) {
  const groups = {};
  for (const row of rows) {
    const key = `${row.Type}_${row.Strike}_${row.Expires}`;
    if (!groups[key]) {
      groups[key] = {
        type: row.Type,
        strike: row.Strike,
        expires: row.Expires,
        count: 0,
        totalSize: 0,
        totalPremium: 0,
      };
    }
    groups[key].count += 1;
    groups[key].totalSize += parseInt(row.Size, 10) || 0;
    groups[key].totalPremium += parseFloat(row.Premium) || 0;
  }
  return groups;
}

// ---- 輸出格式 ----
function formatExpiry(isoStr) {
  return (isoStr || '').slice(0, 10); // YYYY-MM-DD
}

function formatMoney(n) {
  return '$' + Math.round(n).toLocaleString('en-US');
}

function padRow(cols, widths) {
  return cols.map((c, i) => String(c).padEnd(widths[i])).join(' ');
}

function printSummary(symbol, rows) {
  const calls = rows.filter(r => r.Type === 'Call');
  const puts = rows.filter(r => r.Type === 'Put');
  const callPremium = calls.reduce((s, r) => s + (parseFloat(r.Premium) || 0), 0);
  const putPremium = puts.reduce((s, r) => s + (parseFloat(r.Premium) || 0), 0);

  console.log('='.repeat(72));
  console.log(`  ${symbol} Options Flow 統計分析`);
  console.log('='.repeat(72));
  console.log(`總交易筆數：${rows.length}（Call: ${calls.length}, Put: ${puts.length}）`);
  console.log(`Call 總權利金：${formatMoney(callPremium)}`);
  console.log(`Put  總權利金：${formatMoney(putPremium)}`);
  console.log(`Call/Put 權利金比：${putPremium > 0 ? (callPremium / putPremium).toFixed(2) : 'N/A'}`);
  console.log('');
}

function printTopSingleTrades(rows) {
  const widths = [6, 7, 12, 8, 7, 7, 14, 8];
  const sorted = [...rows].sort((a, b) => (parseFloat(b.Premium) || 0) - (parseFloat(a.Premium) || 0));
  console.log(`--- 單筆交易明細，依該筆權利金排序，前 ${TOP_N} 筆 ---\n`);
  console.log(padRow(['Type', 'Strike', 'Expires', 'Trade', 'Size', 'Side', 'Premium', 'Time'], widths));
  console.log('-'.repeat(76));
  sorted.slice(0, TOP_N).forEach(r => {
    console.log(padRow([
      r.Type,
      '$' + r.Strike,
      formatExpiry(r.Expires),
      '$' + r.Trade,
      r.Size,
      r.Side,
      formatMoney(parseFloat(r.Premium) || 0),
      r.Time,
    ], widths));
  });
  console.log('');
}

function printTopByExpiry(groupArr) {
  const widths = [6, 8, 12, 8, 8, 14];
  console.log(`--- 依到期日排序（最近到期優先），前 ${TOP_N} 筆 ---\n`);
  console.log(padRow(['Type', 'Strike', 'Expires', 'Trades', 'Size', 'Premium'], widths));
  console.log('-'.repeat(72));
  groupArr.slice(0, TOP_N).forEach(g => {
    console.log(padRow([
      g.type,
      '$' + g.strike,
      formatExpiry(g.expires),
      g.count,
      g.totalSize,
      formatMoney(g.totalPremium),
    ], widths));
  });
  console.log('');
}

function printTopByPremiumOverall(groupArr) {
  const widths = [6, 8, 12, 8, 8, 14];
  const sorted = [...groupArr].sort((a, b) => b.totalPremium - a.totalPremium);
  console.log(`--- 不分到期日，依總權利金排序，前 ${TOP_N} 筆（最大資金押注） ---\n`);
  console.log(padRow(['Type', 'Strike', 'Expires', 'Trades', 'Size', 'Premium'], widths));
  console.log('-'.repeat(72));
  sorted.slice(0, TOP_N).forEach(g => {
    console.log(padRow([
      g.type,
      '$' + g.strike,
      formatExpiry(g.expires),
      g.count,
      g.totalSize,
      formatMoney(g.totalPremium),
    ], widths));
  });
  console.log('');
}

function printExpiryList(groupArr) {
  const uniqueExpiries = [...new Set(groupArr.map(g => formatExpiry(g.expires)))]
    .sort((a, b) => new Date(a) - new Date(b));
  console.log('--- 本次資料涵蓋的到期日清單 ---\n');
  console.log(uniqueExpiries.join('、'));
  console.log('');
}

main();
