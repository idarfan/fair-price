/** 投資名人堂 API 型別（對應 HallOfFame::OfficialDirectory 的輸出）。 */

export type Tab = "congress" | "executive";

export interface OfficialCard {
  slug: string;
  display_name: string;
  district: string | null;
  title: string | null;
  latest_filing_date: string | null;
  ptr_count: number;
  needs_review_count: number;
}

export interface HoldingRow {
  id: number;
  asset_name: string;
  ticker: string | null;
  owner: string;
  value_label: string | null;
  value_min: number | null;
  value_max: number | null;
  unbounded: boolean;
  estimated: number | null;
  lower: number | null;
  upper: number | null;
  excluded_reason: string | null;
  needs_review: boolean;
}

export interface HoldingsViewData {
  rows: HoldingRow[];
  upper_note: string | null;
  excluded_count: number;
}

export interface Holdings {
  doc_id: string;
  year: number | null;
  filing_date: string | null;
  as_of: string | null;
  parse_status: string;
  parse_error: string | null;
  pdf_url: string | null;
  views: { all: HoldingsViewData; securities: HoldingsViewData };
}

export interface OptionInfo {
  right: string | null;
  strike: number | null;
  expiration: string | null;
  contracts: string | null;
  premium: string | null;
  source: string | null;
  source_label: string | null;
  calc_note: string | null;
}

export interface TradeRow {
  id: number;
  tx_date: string | null;
  notified_date: string | null;
  asset_name: string;
  ticker: string | null;
  owner: string;
  tx_type: string | null;
  amount_label: string | null;
  amount_min: number | null;
  amount_max: number | null;
  doc_id: string;
  pdf_url: string | null;
  needs_review: boolean;
  excluded_reason: string | null;
  option: OptionInfo | null;
}

export interface TradeShare {
  key: string;
  count: number;
  mid: number;
  unbounded: boolean;
  estimated: number | null;
}

export interface Trades {
  since: string | null;
  rows: TradeRow[];
  shares: { purchase: TradeShare[]; sale: TradeShare[] };
}

export interface Profile {
  official: {
    slug: string;
    display_name: string;
    district: string | null;
    title: string | null;
  };
  holdings: Holdings | null;
  trades: Trades;
  synced_at: Record<string, string | null>;
}
