import { createRoot } from "react-dom/client";
import { OptionProfitCalcApp } from "../option_profit_calc/OptionProfitCalcApp";

const el = document.getElementById("option-profit-calc-root");
if (el) {
  createRoot(el).render(<OptionProfitCalcApp />);
}
