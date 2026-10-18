import React from "react";
import { createRoot } from "react-dom/client";
import HallOfFameApp from "../hall_of_fame/HallOfFameApp";
import { parseCards } from "../hall_of_fame/parse";

const el = document.getElementById("hall-of-fame-root");
if (el) {
  const cards = parseCards(JSON.parse(el.dataset.cards || "[]"));
  const initialTab = el.dataset.tab === "executive" ? "executive" : "congress";
  createRoot(el).render(
    <HallOfFameApp initialTab={initialTab} cards={cards} />,
  );
}
