/**
 * 由 layout 以獨立 <script> 載入的第三方全域，以及本專案掛在 window 上的東西。
 *
 * 這些不是 npm 相依（見 app/views/layouts/application.html.erb），所以沒有隨附
 * 的型別定義。這裡只宣告 behaviors 實際用到的那部分形狀——刻意不追求完整覆蓋
 * 第三方 API，用不到的成員留白比抄一份會過期的定義好。
 */

interface FairPriceTrack {
  command(name: string, payload?: unknown): void;
}


declare global {
  interface DriverStep {
    element: Element | string;
    popover: {
      title: string;
      description: string;
      side?: string;
      align?: string;
    };
  }

  interface DriverConfig {
    animate?: boolean;
    allowClose?: boolean;
    overlayOpacity?: number;
    showProgress?: boolean;
    steps: DriverStep[];
  }

  interface DriverInstance {
    drive(): void;
  }

  interface Window {
    FairPriceTrack?: FairPriceTrack;
    driver?: { js?: { driver?: (config: DriverConfig) => DriverInstance } };
    // 教學頁把朗讀函式掛上 window 供其他區塊呼叫（見 behaviors/ivEducationTts.ts）
    ttsSpeak?: (text: string, gender: string) => void;
    // IV 分析頁的儀表板模式切換（behaviors/ivAnalysis.ts 掛上，Phlex 端也會呼叫）
    switchDashMode?: (mode: string) => void;
    // 註：window.mountTechChart 由 entrypoints/technicals.tsx 自行宣告（實作也在那），
    // 這裡不重複宣告，否則兩份簽名不一致會觸發 TS2717。
  }

  // Chart.js 4.x（CDN UMD build）。只宣告 behaviors 實際碰到的成員——
  // 刻意不抄一份會過期的完整定義。
  interface ChartScaleInstance {
    width: number;
  }

  interface ChartDatasetMeta {
    data: { x: number; y: number }[];
  }

  interface ChartInstance {
    destroy(): void;
    update(): void;
    canvas: HTMLCanvasElement;
    scales: Record<string, ChartScaleInstance | undefined>;
    tooltip?: { _active?: { index: number }[] };
    getDatasetMeta(index: number): ChartDatasetMeta;
    data: unknown;
    config: unknown;
    width: number;
    height: number;
  }

  const Chart: {
    new (
      ctx: CanvasRenderingContext2D | HTMLCanvasElement,
      config: unknown,
    ): ChartInstance;
    getChart(el: HTMLCanvasElement | string): ChartInstance | undefined;
  };

  // SortableJS 1.15（CDN）
  const Sortable: {
    create(el: HTMLElement, options: Record<string, unknown>): unknown;
    get(el: HTMLElement): unknown;
  };

  // NProgress 0.2（CDN）
  const NProgress: {
    start(): void;
    done(): void;
    set(n: number): void;
    configure(options: Record<string, unknown>): void;
  };

  // jsPDF 2.5（vendor 本地檔）。只宣告 behaviors 用到的部分。
  const jspdf: {
    jsPDF: new (options?: Record<string, unknown>) => {
      internal: { pageSize: { getWidth(): number; getHeight(): number } };
      addImage(
        data: string, format: string, x: number, y: number,
        w: number, h: number, alias?: string, compression?: string,
      ): void;
      addPage(): void;
      save(filename: string): void;
    };
  };

  // html-to-image 1.11（vendor 本地檔，見 app/assets/javascripts/）
  const htmlToImage: {
    toPng(
      node: HTMLElement,
      options?: Record<string, unknown>,
    ): Promise<string>;
    toBlob(
      node: HTMLElement,
      options?: Record<string, unknown>,
    ): Promise<Blob | null>;
  };
}

export {};
