import React, { useEffect, useState } from "react";
import type { OfficialCard, Profile, Tab } from "./types";
import { parseProfile } from "./parse";
import { DASH, SYNC_LABELS, fmtDateTime } from "./format";
import HoldingsSection from "./components/HoldingsSection";
import TradesSection from "./components/TradesSection";

export const DISCLAIMER =
  "資料來源：美國眾議院書記處、美國政府倫理辦公室公開申報。金額為申報區間，佔比為估算值。依 Ethics in Government Act，本資料不得用於商業、信用評等或募款用途。";

const TABS: { key: Tab; label: string }[] = [
  { key: "congress", label: "國會議員" },
  { key: "executive", label: "行政政要" },
];

function OfficialDetail({ slug }: { slug: string }) {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetch(`/api/v1/hall_of_fame/officials/${encodeURIComponent(slug)}`)
      .then(async (res) => {
        const data: unknown = await res.json();
        const parsed = res.ok ? parseProfile(data) : null;
        if (cancelled) return;
        if (parsed) {
          setProfile(parsed);
          setError(null);
        } else {
          setError("無法載入人物資料");
        }
      })
      .catch(() => {
        if (!cancelled) setError("無法載入人物資料");
      });
    return () => {
      cancelled = true;
    };
  }, [slug]);

  if (error) return <p className="text-sm text-red-600">{error}</p>;
  if (!profile) return <p className="text-sm text-gray-500">載入中…</p>;

  return (
    <div className="space-y-6" data-testid="official-detail">
      <p className="text-xs text-gray-500">
        資料更新時間：
        {Object.entries(SYNC_LABELS)
          .map(
            ([k, label]) =>
              `${label} ${fmtDateTime(profile.synced_at[k] ?? null)}`,
          )
          .join("｜")}
      </p>
      <HoldingsSection holdings={profile.holdings} />
      <TradesSection trades={profile.trades} />
    </div>
  );
}

function CongressTab({ cards }: { cards: OfficialCard[] }) {
  const [selected, setSelected] = useState<string | null>(null);
  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {cards.map((c) => (
          <button
            key={c.slug}
            type="button"
            onClick={() => setSelected(c.slug === selected ? null : c.slug)}
            aria-expanded={c.slug === selected}
            data-testid="official-card"
            className={`rounded-lg border p-3 text-left ${c.slug === selected ? "border-blue-500 bg-blue-50" : "border-gray-200 bg-white"}`}
          >
            <div className="font-semibold text-gray-900">{c.display_name}</div>
            <div className="text-xs text-gray-500">
              選區 {c.district ?? DASH}
            </div>
            <div className="mt-1 text-xs text-gray-600">
              最新申報日 {c.latest_filing_date ?? DASH}｜PTR {c.ptr_count} 筆
            </div>
            {c.needs_review_count > 0 && (
              <div className="text-xs text-amber-700">
                {c.needs_review_count} 份待人工確認
              </div>
            )}
          </button>
        ))}
      </div>
      {selected && <OfficialDetail key={selected} slug={selected} />}
    </div>
  );
}

export default function HallOfFameApp({
  initialTab,
  cards,
}: {
  initialTab: Tab;
  cards: OfficialCard[];
}) {
  const [tab, setTab] = useState<Tab>(initialTab);
  return (
    <div className="space-y-4">
      <h1 className="text-xl font-bold text-gray-900">投資名人堂</h1>
      <div className="flex gap-2 border-b border-gray-200" role="tablist">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => setTab(t.key)}
            className={`-mb-px border-b-2 px-3 py-2 text-sm ${tab === t.key ? "border-blue-600 font-semibold text-blue-700" : "border-transparent text-gray-600"}`}
          >
            {t.label}
          </button>
        ))}
      </div>
      {tab === "congress" ? (
        <CongressTab cards={cards} />
      ) : (
        <p className="text-sm text-gray-500" data-testid="executive-pending">
          第二期建置中
        </p>
      )}
      <footer className="border-t border-gray-200 pt-3 text-xs text-gray-500">
        {DISCLAIMER}
      </footer>
    </div>
  );
}
