import { createRoot } from "react-dom/client";
import OptionPriceTrackerApp from "../option_price_tracker/OptionPriceTrackerApp";
import type { TrackedTicker } from "../option_price_tracker/types";

const el = document.getElementById("option-price-tracker-root");
if (el) {
  const initialTickers: TrackedTicker[] = JSON.parse(
    el.dataset.tickers ?? "[]",
  );
  // 追蹤清單是共用的蒐集設定，只有 admin 能改（後端由 require_admin! 把關，
  // 這個旗標只負責讓 UI 誠實呈現，不是安全邊界）。
  const canManage = el.dataset.canManage === "true";

  createRoot(el).render(
    <OptionPriceTrackerApp initialTickers={initialTickers} canManage={canManage} />,
  );
}
