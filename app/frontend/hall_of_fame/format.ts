/** 名人堂顯示格式。數值缺漏一律顯示「—」。 */

export const DASH = "—";

export function fmtPct(value: number | null): string {
  return value === null ? DASH : `${value.toFixed(2)}%`;
}

export function fmtUsd(value: number | null): string {
  return value === null
    ? DASH
    : `$${Math.round(value).toLocaleString("en-US")}`;
}

/** 申報區間：無上限顯示「≥ min」（§4）。 */
export function fmtRange(min: number | null, max: number | null): string {
  if (min === null) return DASH;
  if (max === null) return `≥ ${fmtUsd(min)}`;
  return `${fmtUsd(min)} – ${fmtUsd(max)}`;
}

// 一般區間（$1,001 - $15,000）與無上限（Over $50,000,000）才用數值組字；其餘照申報原字串顯示。
const REGULAR_RANGE = /^\$[\d,]+ - \$[\d,]+$/;
const OPEN_ENDED = /^Over \$/;

/**
 * 申報金額欄（P5 r1 問題 1、質詢 2）：金額無法對照（min 為空）或標籤不是一般區間
 * （None、Spouse/DC Over $1,000,000、精確金額 $15.00 等）時顯示原字串，不讓「None」變成「$0 – $0」。
 */
export function fmtAmount(
  label: string | null,
  min: number | null,
  max: number | null,
): string {
  if (min === null) return label ?? DASH;
  if (label === null || REGULAR_RANGE.test(label) || OPEN_ENDED.test(label))
    return fmtRange(min, max);
  return label;
}

export function fmtDateTime(iso: string | null): string {
  if (!iso) return DASH;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return DASH;
  return d.toLocaleString("zh-TW", { timeZone: "Asia/Taipei", hour12: false });
}

export const TX_TYPE_LABELS: Record<string, string> = {
  P: "買",
  S: "賣",
  S_partial: "部分賣出",
  E: "交換",
};

export const OWNER_LABELS: Record<string, string> = {
  self: "本人",
  SP: "配偶",
  JT: "共同",
  DC: "子女",
};

export const RIGHT_LABELS: Record<string, string> = {
  call: "Call",
  put: "Put",
};

export const SYNC_LABELS: Record<string, string> = {
  index: "索引同步",
  pdf_parse: "PDF 解析",
  options: "期權分析",
};
