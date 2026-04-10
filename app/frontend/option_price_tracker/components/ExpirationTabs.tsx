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
    <div className="flex items-center gap-1 px-3 py-2 overflow-x-auto border-b border-gray-700 bg-gray-850 shrink-0">
      {expirations.map((exp) => {
        const dte = calcDte(exp);
        const isSelected = exp === selected;
        return (
          <button
            key={exp}
            onClick={() => onSelect(exp)}
            className={`shrink-0 px-3 py-1.5 rounded text-xs font-medium transition-colors whitespace-nowrap ${
              isSelected
                ? "bg-blue-600 text-white"
                : dte <= 7
                  ? "bg-gray-700 text-red-300 hover:bg-gray-600"
                  : "bg-gray-700 text-gray-300 hover:bg-gray-600"
            }`}
          >
            {fmtDate(exp)}
            <span
              className={`ml-1 text-xs ${isSelected ? "text-blue-200" : "text-gray-500"}`}
            >
              {dte}d
            </span>
          </button>
        );
      })}
    </div>
  );
}
