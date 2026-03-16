export interface Holder {
  name:        string
  pct:         number | null
  value:       number | null
  filing_date: string | null
  pct_change:  number | null  // Yahoo Finance 提供的 vs 上季股份變化（0.019 = +1.9%）
}

export interface ApiSnapshot {
  quarter:           string
  date:              string
  institutional_pct: number | null
  insider_pct:       number | null
  institution_count: number | null
  holders:           Holder[]
}

export interface ApiResponse {
  snapshots: ApiSnapshot[]
  previous:  ApiSnapshot | null
}

// 保留舊型別供 SymbolList 使用
export type { ApiSnapshot as Snapshot }
