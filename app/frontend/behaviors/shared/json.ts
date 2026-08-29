/**
 * fetch 回應的 runtime 收窄工具。
 *
 * `response.json()` 回傳 `any`，直接取用等同放棄型別檢查；而 global rules 禁止
 * `as` 強轉、要求用 Zod 驗證——但這個專案沒裝 Zod（npm install 目前卡在 vite 的
 * peer dependency 衝突）。所以用一組手寫的收窄函式取代：形狀都很小，手寫反而
 * 比拉一個 schema library 進來直接，而且全程用 type predicate，沒有任何 `as`。
 *
 * 用法刻意保守：取不到就回 undefined，由呼叫端決定 fallback，不替它猜。
 */

/** 是不是可用字串鍵取值的物件（null 與陣列都不算）。 */
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** 取字串欄位，型別不符回 undefined。 */
export function str(source: unknown, key: string): string | undefined {
  if (!isRecord(source)) return undefined;
  const v = source[key];
  return typeof v === "string" ? v : undefined;
}

/** 取數字欄位，型別不符或 NaN 回 undefined。 */
export function num(source: unknown, key: string): number | undefined {
  if (!isRecord(source)) return undefined;
  const v = source[key];
  return typeof v === "number" && !isNaN(v) ? v : undefined;
}

/** 取陣列欄位，型別不符回空陣列。 */
export function arr(source: unknown, key: string): unknown[] {
  if (!isRecord(source)) return [];
  const v = source[key];
  return Array.isArray(v) ? v : [];
}

/** 取陣列欄位的第一個字串元素（例如後端回傳的 errors 陣列）。 */
export function firstString(source: unknown, key: string): string | undefined {
  const first = arr(source, key)[0];
  return typeof first === "string" ? first : undefined;
}

/**
 * parseFloat 語意的數字讀取：接受數字，也接受「數字字串」。
 *
 * Rails 把 BigDecimal 欄位序列化成字串（例如 IV watchlist 的 skew_rank 回
 * `"78.87"`、strike 回 `"100.0"`）。型別化前這些欄位都經過 `parseFloat`，
 * 所以字串照樣能用；改成嚴格的 `num()` 之後整批被丟掉，Skew Rank 與履約價
 * 欄位全變成「—」。凡是原本走 parseFloat 的欄位，一律用這支。
 *
 * `num()` 保留給原本就用 `typeof === 'number'` 判斷的地方（例如價差頁的
 * fmt()），那裡字串本來就會顯示成「—」，不能一起放寬。
 */
export function numeric(source: unknown, key: string): number | undefined {
  if (!isRecord(source)) return undefined;
  const v = source[key];
  if (typeof v === "number") return isNaN(v) ? undefined : v;
  if (typeof v === "string") {
    const n = parseFloat(v);
    return isNaN(n) ? undefined : n;
  }
  return undefined;
}
