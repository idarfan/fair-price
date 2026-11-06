import React from "react";

/** needs_review 警示標記（§1-5）：滑過顯示原因。 */
export default function ReviewBadge({ note }: { note: string | null }) {
  return (
    <span
      className="inline-flex items-center rounded bg-amber-100 px-1.5 py-0.5 text-[11px] text-amber-800"
      data-testid="needs-review"
      title={note ?? "解析結果待人工確認"}
    >
      ⚠ 待人工確認
    </span>
  );
}
