export interface TrackedTicker {
  id: number;
  symbol: string;
  name: string | null;
  active: boolean;
  last_snapshot_date: string | null;
}

export interface OptionSnapshotRow {
  id: number;
  contract_symbol: string;
  option_type: "call" | "put";
  expiration: string;
  strike: number;
  bid: number | null;
  ask: number | null;
  last_price: number | null;
  implied_volatility: number | null;
  volume: number | null;
  open_interest: number | null;
  in_the_money: boolean;
  underlying_price: number | null;
  snapshot_date: string;
}

export interface SnapshotsResponse {
  symbol: string;
  snapshots: OptionSnapshotRow[];
  expirations: string[];
}

export interface PremiumTrendPoint {
  date: string;
  snapped_at: string; // ISO 8601 UTC datetime, e.g. "2026-04-09T19:30:00.000Z"
  bid: number | null;
  ask: number | null;
  last_price: number | null;
  implied_volatility: number | null;
  volume: number | null;
  open_interest: number | null;
  underlying_price: number | null;
}

export type OptionType = "put" | "call" | "all";
