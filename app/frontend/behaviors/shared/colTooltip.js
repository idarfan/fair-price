/**
 * 兩支價差試算頁共用的欄位說明 tooltip（稽核 M-6）。
 *
 * hover 顯示深色小卡、點擊改用 driver.js 的 popover 標示該欄位。抽出前
 * bullPutTooltips.js 與 bullCallTooltips.js 的這段是逐字相同的，差別只有
 * tip 容器的 id 前綴。
 *
 * 重要：容器 id 必須維持 `<prefix>-col-tip`——app/assets/tailwind/application.css
 * 針對 #bpus-col-tip 與 #bcvs-col-tip 各有一份樣式，而且 .tip-t 的字級不同
 * （13px vs 22px），改 id 會讓兩頁的 tooltip 樣式一起壞掉。
 *
 * TODO：型別化成 .ts。
 */

/**
 * @param {{ prefix: string, colExplain: Record<string, {title: string, desc: string}> }} options
 * @returns {{ drv: Function, hide: Function }} 供呼叫端擴充（例如 bcvs 的全頁導覽）
 */
export function initColTooltip(options) {
  var prefix = options.prefix;
  var colExplain = options.colExplain;

  var tip = document.createElement("div");
  tip.id = prefix + "-col-tip";
  tip.innerHTML = '<div class="tip-t"></div><div class="tip-b"></div>';
  document.body.appendChild(tip);
  var tT = tip.querySelector(".tip-t"),
    tB = tip.querySelector(".tip-b");

  function posTip(e) {
    var x = e.clientX + 14,
      y = e.clientY + 12,
      w = tip.offsetWidth || 280,
      h = tip.offsetHeight || 100;
    if (x + w > window.innerWidth - 10) x = e.clientX - w - 10;
    if (y + h > window.innerHeight - 10) y = e.clientY - h - 10;
    tip.style.left = x + "px";
    tip.style.top = y + "px";
  }

  function hide() {
    tip.style.opacity = "0";
  }

  document.addEventListener("mouseover", function (e) {
    var el = e.target.closest("[data-tip-key]");
    if (el) {
      var d = colExplain[el.dataset.tipKey];
      if (!d) return;
      tT.textContent = d.title;
      tB.textContent = d.desc;
      tip.style.opacity = "1";
      posTip(e);
    } else {
      hide();
    }
  });
  document.addEventListener("mousemove", function (e) {
    if (tip.style.opacity !== "0") posTip(e);
  });
  document.addEventListener("mouseout", function (e) {
    if (!e.target.closest("[data-tip-key]")) hide();
  });

  function drv() {
    return window.driver && window.driver.js && window.driver.js.driver;
  }

  document.addEventListener("click", function (e) {
    var el = e.target.closest("[data-tip-key]");
    if (el && drv()) {
      var d = colExplain[el.dataset.tipKey];
      if (!d) return;
      hide();
      drv()({
        animate: true,
        allowClose: true,
        overlayOpacity: 0.35,
        steps: [
          {
            element: el,
            popover: {
              title: d.title,
              description: d.desc,
              side: "bottom",
              align: "center",
            },
          },
        ],
      }).drive();
    }
  });

  return { drv: drv, hide: hide };
}
