interface Props {
  dates: string[];
  selected: string;
  onSelect: (date: string) => void;
}

function fmtDate(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return d.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default function SnapshotDateTabs({ dates, selected, onSelect }: Props) {
  if (dates.length <= 1) return null;

  return (
    <div className="flex items-center gap-1 px-3 py-1.5 border-b border-gray-200 bg-white shrink-0">
      <span className="text-xs text-gray-400 mr-1 shrink-0">快照日期</span>
      {dates.map((date) => (
        <button
          key={date}
          onClick={() => onSelect(date)}
          className={`shrink-0 px-2.5 py-1 rounded text-xs font-medium transition-colors whitespace-nowrap ${
            date === selected
              ? "bg-blue-600 text-white"
              : "bg-gray-100 text-gray-600 hover:bg-gray-200"
          }`}
        >
          {fmtDate(date)}
        </button>
      ))}
    </div>
  );
}
