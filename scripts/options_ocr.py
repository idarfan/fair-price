#!/usr/bin/env python3
"""
使用 EasyOCR 從期權截圖提取文字。
用法: python3 options_ocr.py <image_path>
輸出: JSON { "text": "...", "lines": [...] }
"""
import sys
import json
import os

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "缺少圖片路徑"}))
        sys.exit(1)

    image_path = sys.argv[1]
    if not os.path.exists(image_path):
        print(json.dumps({"error": f"找不到圖片: {image_path}"}))
        sys.exit(1)

    try:
        import easyocr
        import numpy as np
        from PIL import Image

        # 讀取圖片
        img = Image.open(image_path).convert("RGB")

        # 初始化 reader（英文 + 繁中，gpu=False 確保 CPU 可用）
        reader = easyocr.Reader(["en"], gpu=False, verbose=False)
        results = reader.readtext(np.array(img))

        # 依 Y 座標排序（上→下），同行內依 X 座標排序（左→右）
        results.sort(key=lambda r: (round(r[0][0][1] / 20), r[0][0][0]))

        lines = []
        for bbox, text, conf in results:
            if conf >= 0.2 and text.strip():
                lines.append({
                    "text": text.strip(),
                    "conf": round(conf, 3),
                    "y":    round(bbox[0][1])
                })

        # 合併成純文字（相近 Y 視為同一行）
        merged_lines = []
        current_y    = -1
        current_line = []
        for item in lines:
            if abs(item["y"] - current_y) < 25 and current_y >= 0:
                current_line.append(item["text"])
            else:
                if current_line:
                    merged_lines.append(" ".join(current_line))
                current_line = [item["text"]]
                current_y    = item["y"]
        if current_line:
            merged_lines.append(" ".join(current_line))

        full_text = "\n".join(merged_lines)
        print(json.dumps({
            "text":  full_text,
            "lines": merged_lines,
            "count": len(merged_lines)
        }, ensure_ascii=False))

    except ImportError as e:
        print(json.dumps({"error": f"套件未安裝: {e}"}))
        sys.exit(1)
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    main()
