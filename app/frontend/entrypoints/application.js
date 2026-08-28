// 全站活躍度追蹤:頁面停留時間(sendBeacon)+ 指令使用(data-track-action 委派)。
// auth-and-activity.md 階段 8/9。

function computeReferrerPath() {
  var ref = document.referrer;
  if (!ref) return null;
  try {
    var url = new URL(ref);
    return url.origin === window.location.origin ? url.pathname : "external";
  } catch {
    return "external";
  }
}

function initPageViewTracking() {
  var startedAt = Date.now();
  var activityToken = crypto.randomUUID();
  var referrerPath = computeReferrerPath();
  var path = window.location.pathname;
  var sent = false;

  function sendBeacon(finalSend) {
    var durationMs = Date.now() - startedAt;
    var payload = new FormData();
    payload.append("activity_token", activityToken);
    payload.append("path", path);
    if (referrerPath !== null) payload.append("referrer_path", referrerPath);
    payload.append("duration_ms", String(durationMs));
    navigator.sendBeacon("/track/page_view", payload);
    if (finalSend) sent = true;
  }

  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "hidden" && !sent) sendBeacon(true);
  });
  window.addEventListener("pagehide", function () {
    if (!sent) sendBeacon(true);
  });

  // 長時間停留同頁:每 5 分鐘用同一個 activity_token 補送心跳,防資料因崩潰遺失。
  setInterval(
    function () {
      if (!sent) sendBeacon(false);
    },
    5 * 60 * 1000,
  );
}

function gatherMetadata(el) {
  var explicit = el.getAttribute("data-track-metadata");
  if (explicit) {
    try {
      return JSON.parse(explicit);
    } catch {
      // fall through to form-based metadata
    }
  }
  var form = el.closest("form");
  if (form) {
    return Object.fromEntries(new FormData(form).entries());
  }
  return {};
}

function trackCommand(actionName, metadata) {
  var payload = new FormData();
  payload.append("action_name", actionName);
  payload.append("metadata", JSON.stringify(metadata || {}));
  navigator.sendBeacon("/track/command", payload);
}

function initCommandTracking() {
  document.addEventListener("click", function (e) {
    var el = e.target.closest("[data-track-action]");
    if (!el) return;
    trackCommand(el.getAttribute("data-track-action"), gatherMetadata(el));
  });
}

window.FairPriceTrack = { command: trackCommand };

initPageViewTracking();
initCommandTracking();
