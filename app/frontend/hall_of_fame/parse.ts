/**
 * API 回應的 runtime 收窄（專案未裝 Zod，沿用 behaviors/shared/json.ts 的手寫收窄，不用 `as`）。
 * 欄位缺漏或型別不符一律落到 null／空陣列，由畫面顯示「—」，不替資料猜值。
 */
import { arr, isRecord, num, str } from "../behaviors/shared/json";
import type {
  Holdings,
  HoldingRow,
  HoldingsViewData,
  OfficialCard,
  OptionInfo,
  Profile,
  TradeRow,
  TradeShare,
  Trades,
} from "./types";

const strOrNull = (s: unknown, k: string): string | null => str(s, k) ?? null;
const numOrNull = (s: unknown, k: string): number | null => num(s, k) ?? null;
const bool = (s: unknown, k: string): boolean => isRecord(s) && s[k] === true;

export function parseCards(source: unknown): OfficialCard[] {
  const list = Array.isArray(source) ? source : arr(source, "officials");
  return list.filter(isRecord).map((c) => ({
    slug: str(c, "slug") ?? "",
    display_name: str(c, "display_name") ?? "",
    district: strOrNull(c, "district"),
    title: strOrNull(c, "title"),
    latest_filing_date: strOrNull(c, "latest_filing_date"),
    ptr_count: num(c, "ptr_count") ?? 0,
    needs_review_count: num(c, "needs_review_count") ?? 0,
  }));
}

function parseHoldingRow(r: unknown): HoldingRow {
  return {
    id: num(r, "id") ?? 0,
    asset_name: str(r, "asset_name") ?? "",
    ticker: strOrNull(r, "ticker"),
    owner: str(r, "owner") ?? "",
    value_label: strOrNull(r, "value_label"),
    value_min: numOrNull(r, "value_min"),
    value_max: numOrNull(r, "value_max"),
    unbounded: bool(r, "unbounded"),
    estimated: numOrNull(r, "estimated"),
    lower: numOrNull(r, "lower"),
    upper: numOrNull(r, "upper"),
    excluded_reason: strOrNull(r, "excluded_reason"),
    needs_review: bool(r, "needs_review"),
  };
}

function parseView(v: unknown): HoldingsViewData {
  return {
    rows: arr(v, "rows").map(parseHoldingRow),
    upper_note: strOrNull(v, "upper_note"),
    excluded_count: num(v, "excluded_count") ?? 0,
  };
}

function parseHoldings(h: unknown): Holdings | null {
  if (!isRecord(h)) return null;
  const views = isRecord(h.views) ? h.views : {};
  return {
    doc_id: str(h, "doc_id") ?? "",
    year: numOrNull(h, "year"),
    filing_date: strOrNull(h, "filing_date"),
    as_of: strOrNull(h, "as_of"),
    parse_status: str(h, "parse_status") ?? "",
    parse_error: strOrNull(h, "parse_error"),
    pdf_url: strOrNull(h, "pdf_url"),
    views: {
      all: parseView(views.all),
      securities: parseView(views.securities),
    },
  };
}

function parseOption(o: unknown): OptionInfo | null {
  if (!isRecord(o)) return null;
  return {
    right: strOrNull(o, "right"),
    strike: numOrNull(o, "strike"),
    expiration: strOrNull(o, "expiration"),
    contracts: strOrNull(o, "contracts"),
    premium: strOrNull(o, "premium"),
    source: strOrNull(o, "source"),
    source_label: strOrNull(o, "source_label"),
    calc_note: strOrNull(o, "calc_note"),
  };
}

function parseTradeRow(r: unknown): TradeRow {
  return {
    id: num(r, "id") ?? 0,
    tx_date: strOrNull(r, "tx_date"),
    notified_date: strOrNull(r, "notified_date"),
    asset_name: str(r, "asset_name") ?? "",
    ticker: strOrNull(r, "ticker"),
    owner: str(r, "owner") ?? "",
    tx_type: strOrNull(r, "tx_type"),
    amount_label: strOrNull(r, "amount_label"),
    amount_min: numOrNull(r, "amount_min"),
    amount_max: numOrNull(r, "amount_max"),
    doc_id: str(r, "doc_id") ?? "",
    pdf_url: strOrNull(r, "pdf_url"),
    needs_review: bool(r, "needs_review"),
    excluded_reason: strOrNull(r, "excluded_reason"),
    option: isRecord(r) ? parseOption(r.option) : null,
  };
}

function parseShare(s: unknown): TradeShare {
  return {
    key: str(s, "key") ?? "",
    count: num(s, "count") ?? 0,
    mid: num(s, "mid") ?? 0,
    unbounded: bool(s, "unbounded"),
    estimated: numOrNull(s, "estimated"),
  };
}

function parseTrades(t: unknown): Trades {
  const shares = isRecord(t) && isRecord(t.shares) ? t.shares : {};
  return {
    since: strOrNull(t, "since"),
    rows: arr(t, "rows").map(parseTradeRow),
    shares: {
      purchase: arr(shares, "purchase").map(parseShare),
      sale: arr(shares, "sale").map(parseShare),
    },
  };
}

export function parseProfile(source: unknown): Profile | null {
  if (!isRecord(source) || !isRecord(source.official)) return null;
  const o = source.official;
  const synced: Record<string, string | null> = {};
  if (isRecord(source.synced_at)) {
    for (const [k, v] of Object.entries(source.synced_at))
      synced[k] = typeof v === "string" ? v : null;
  }
  return {
    official: {
      slug: str(o, "slug") ?? "",
      display_name: str(o, "display_name") ?? "",
      district: strOrNull(o, "district"),
      title: strOrNull(o, "title"),
    },
    holdings: parseHoldings(source.holdings),
    trades: parseTrades(source.trades),
    synced_at: synced,
  };
}
