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
  bid: number | null;
  ask: number | null;
  last_price: number | null;
  implied_volatility: number | null;
  volume: number | null;
  open_interest: number | null;
  underlying_price: number | null;
}

export type OptionType = "put" | "call" | "all";
