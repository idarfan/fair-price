import type { OptionType } from "../types";

interface Props {
  optionType: OptionType;
  expiration: string;
  expirations: string[];
  days: number;
  onOptionTypeChange: (v: OptionType) => void;
  onExpirationChange: (v: string) => void;
  onDaysChange: (v: number) => void;
}

const DAYS_OPTIONS = [
  { label: "30 天", value: 30 },
  { label: "60 天", value: 60 },
  { label: "90 天", value: 90 },
];

export default function FilterBar({
  optionType,
  expiration,
  expirations,
  days,
  onOptionTypeChange,
  onExpirationChange,
  onDaysChange,
}: Props) {
  return (
    <div className="flex flex-wrap items-center gap-3 px-4 py-2 bg-gray-800 border-b border-gray-700">
      {/* Option type */}
      <div className="flex items-center gap-1">
        {(["all", "put", "call"] as OptionType[]).map((t) => (
          <button
            key={t}
            onClick={() => onOptionTypeChange(t)}
            className={`px-2.5 py-1 text-xs rounded font-medium transition-colors ${
              optionType === t
                ? t === "put"
                  ? "bg-red-600 text-white"
                  : t === "call"
                    ? "bg-green-600 text-white"
                    : "bg-blue-600 text-white"
                : "bg-gray-700 text-gray-300 hover:bg-gray-600"
            }`}
          >
            {t === "all" ? "全部" : t.toUpperCase()}
          </button>
        ))}
      </div>

      {/* Expiration */}
      <div className="flex items-center gap-1.5">
        <span className="text-xs text-gray-400">到期日</span>
        <select
          value={expiration}
          onChange={(e) => onExpirationChange(e.target.value)}
          className="bg-gray-700 border border-gray-600 rounded px-2 py-1 text-xs text-white focus:outline-none focus:border-blue-500"
        >
          <option value="">全部</option>
          {expirations.map((exp) => (
            <option key={exp} value={exp}>
              {exp}
            </option>
          ))}
        </select>
      </div>

      {/* Days range */}
      <div className="flex items-center gap-1">
        <span className="text-xs text-gray-400">歷史</span>
        {DAYS_OPTIONS.map((opt) => (
          <button
            key={opt.value}
            onClick={() => onDaysChange(opt.value)}
            className={`px-2 py-1 text-xs rounded transition-colors ${
              days === opt.value
                ? "bg-gray-500 text-white"
                : "bg-gray-700 text-gray-300 hover:bg-gray-600"
            }`}
          >
            {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}
