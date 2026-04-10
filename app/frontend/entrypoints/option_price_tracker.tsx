import { createRoot } from "react-dom/client";
import OptionPriceTrackerApp from "../option_price_tracker/OptionPriceTrackerApp";
import type { TrackedTicker } from "../option_price_tracker/types";

const el = document.getElementById("option-price-tracker-root");
if (el) {
  const initialTickers: TrackedTicker[] = JSON.parse(
    el.dataset.tickers ?? "[]",
  );
  createRoot(el).render(
    <OptionPriceTrackerApp initialTickers={initialTickers} />,
  );
}
