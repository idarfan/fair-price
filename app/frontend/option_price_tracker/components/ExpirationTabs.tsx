interface Props {
  expirations: string[];
  selected: string;
  onSelect: (exp: string) => void;
}

function calcDte(expiration: string): number {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const exp = new Date(expiration);
  return Math.round((exp.getTime() - today.getTime()) / 86_400_000);
}

function fmtDate(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default function ExpirationTabs({
  expirations,
  selected,
  onSelect,
}: Props) {
  return (
    <div className="flex items-center gap-1 px-3 py-2 overflow-x-auto border-b border-gray-200 bg-gray-100 shrink-0">
      {expirations.map((exp) => {
        const dte = calcDte(exp);
        const isSelected = exp === selected;
        return (
          <button
            key={exp}
            onClick={() => onSelect(exp)}
            className={`shrink-0 px-3 py-1.5 rounded text-xs font-medium transition-colors whitespace-nowrap ${
              isSelected
                ? "bg-orange-500 text-white"
                : dte <= 7
                  ? "bg-white border border-red-200 text-red-600 hover:bg-red-50"
                  : "bg-white border border-gray-200 text-gray-700 hover:bg-gray-50"
            }`}
          >
            {fmtDate(exp)}
            <span
              className={`ml-1 text-xs ${isSelected ? "text-orange-100" : "text-gray-400"}`}
            >
              {dte}d
            </span>
          </button>
        );
      })}
    </div>
  );
}
