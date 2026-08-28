/**
 * 共用的 CSRF token 讀取器。
 *
 * `/api/*` 已改為與 UI 共用 session 認證，且 CSRF 由 `null_session` 改成 `exception`
 * （見 app/controllers/concerns/json_auth_gate.rb），因此**所有**非 GET 的 fetch
 * 都必須帶 `X-CSRF-Token`，否則會收到 422 invalid_authenticity_token。
 *
 * token 由 layout 的 `csrf_meta_tags` 輸出。
 */
export function csrfToken(): string {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta?.getAttribute("content") ?? "";
}

/** 寫入請求的標準 headers。`json` 為 false 時不設 Content-Type（給 FormData 用）。 */
export function csrfHeaders(
  options: { json?: boolean } = {},
): Record<string, string> {
  const headers: Record<string, string> = {
    "X-CSRF-Token": csrfToken(),
    "X-Requested-With": "XMLHttpRequest",
  };
  if (options.json) headers["Content-Type"] = "application/json";
  return headers;
}
