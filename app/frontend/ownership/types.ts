export interface TopHolder {
  name:        string
  pct_held:    number | null
  value:       number | null
  report_date: string | null
}

export interface Snapshot {
  id:                     number
  fetched_at:             string
  institutions_pct:       number | null
  insiders_pct:           number | null
  institutions_float_pct: number | null
  institutions_count:     number | null
  top_holders:            TopHolder[]
  source:                 string | null
}

export interface HistoryResponse {
  symbol:    string
  snapshots: Snapshot[]
}
