/*
 * LEAPS 排行表：按住表頭左右拖曳調整欄位順序（僅 admin，順序存 DB 全站套用）。
 *
 * 用 pointer events 而非 HTML5 drag-and-drop，理由有兩個：
 *   1. HTML5 DnD 的游標由瀏覽器決定，做不到「按住拖動時變成移動游標」
 *   2. 表頭的 click 已經被 tooltips.js 用來開欄位教學 popover，我們需要自己
 *      控制「位移超過門檻才算拖曳」，並在拖曳結束後吃掉那一次 click
 */
(function () {
  var DRAG_THRESHOLD_PX = 4;

  function table() {
    return document.querySelector("#leaps-ranking-table[data-col-reorder]");
  }

  function headerCells(tbl) {
    return Array.prototype.slice.call(
      tbl.querySelectorAll("thead th[data-col]"),
    );
  }

  function currentOrder(tbl) {
    return headerCells(tbl).map(function (th) {
      return th.dataset.col;
    });
  }

  /* 一欄 = 表頭那一格 + 每一列同 index 的那一格。DOM 上沒有「欄」這個節點，
     搬動時必須逐列搬，順序才不會跟表頭脫節。 */
  function columnCells(tbl, index) {
    var cells = [];
    var ths = headerCells(tbl);
    if (ths[index]) cells.push(ths[index]);
    tbl.querySelectorAll("tbody tr").forEach(function (tr) {
      var td = tr.children[index];
      if (td) cells.push(td);
    });
    return cells;
  }

  function moveColumn(tbl, from, to) {
    if (from === to) return;
    var ths = headerCells(tbl);
    var rows = [tbl.querySelector("thead tr")].concat(
      Array.prototype.slice.call(tbl.querySelectorAll("tbody tr")),
    );
    rows.forEach(function (row) {
      if (!row) return;
      var cell = row.children[from];
      if (!cell) return;
      // 先移除再插入，所以往右搬時目標 index 會少一格
      var ref = row.children[to > from ? to + 1 : to];
      row.removeChild(cell);
      if (ref) row.insertBefore(cell, ref);
      else row.appendChild(cell);
    });
    return ths;
  }

  function indicator() {
    var el = document.getElementById("leaps-col-drop-line");
    if (!el) {
      el = document.createElement("div");
      el.id = "leaps-col-drop-line";
      el.className = "leaps-col-drop-line";
      document.body.appendChild(el);
    }
    return el;
  }

  /* 游標目前落在哪一欄、要插在它左邊還右邊 */
  function dropTargetIndex(tbl, clientX) {
    var ths = headerCells(tbl).filter(function (th) {
      return !th.classList.contains("leaps-col-hidden");
    });
    for (var i = 0; i < ths.length; i++) {
      var r = ths[i].getBoundingClientRect();
      if (clientX < r.left + r.width / 2)
        return headerCells(tbl).indexOf(ths[i]);
    }
    return ths.length ? headerCells(tbl).indexOf(ths[ths.length - 1]) + 1 : 0;
  }

  function showIndicator(tbl, insertAt) {
    var ths = headerCells(tbl);
    var line = indicator();
    var ref = ths[insertAt] || ths[ths.length - 1];
    if (!ref) return;
    var r = ref.getBoundingClientRect();
    var wrap = tbl.getBoundingClientRect();
    line.style.left = (ths[insertAt] ? r.left : r.right) + "px";
    line.style.top = wrap.top + "px";
    line.style.height = wrap.height + "px";
    line.style.display = "block";
  }

  function hideIndicator() {
    var line = document.getElementById("leaps-col-drop-line");
    if (line) line.style.display = "none";
  }

  function persist(tbl, order, revert) {
    fetch(tbl.dataset.colReorderUrl, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": tbl.dataset.colReorderCsrf,
      },
      credentials: "same-origin",
      body: JSON.stringify({ column_keys: order }),
    })
      .then(function (res) {
        if (res.ok) return;
        return res
          .json()
          .catch(function () {
            return {};
          })
          .then(function (body) {
            throw new Error(
              body.message || "儲存失敗（HTTP " + res.status + "）",
            );
          });
      })
      .catch(function (err) {
        revert();
        window.alert("欄位順序沒有存起來：" + err.message);
      });
  }

  var drag = null; // { th, startX, index, active }
  var suppressNextClick = false;

  document.addEventListener("pointerdown", function (e) {
    if (e.button !== 0) return;
    var tbl = table();
    if (!tbl) return;
    var th = e.target.closest("#leaps-ranking-table thead th[data-col]");
    if (!th) return;

    drag = {
      th: th,
      startX: e.clientX,
      index: headerCells(tbl).indexOf(th),
      active: false,
      tbl: tbl,
    };
  });

  document.addEventListener("pointermove", function (e) {
    if (!drag) return;

    if (!drag.active) {
      if (Math.abs(e.clientX - drag.startX) < DRAG_THRESHOLD_PX) return;
      drag.active = true;
      document.body.classList.add("leaps-col-dragging");
      columnCells(drag.tbl, drag.index).forEach(function (c) {
        c.classList.add("leaps-col-drag-ghost");
      });
    }

    showIndicator(drag.tbl, dropTargetIndex(drag.tbl, e.clientX));
  });

  document.addEventListener("pointerup", function (e) {
    if (!drag) return;
    var d = drag;
    drag = null;
    if (!d.active) return;

    document.body.classList.remove("leaps-col-dragging");
    columnCells(d.tbl, d.index).forEach(function (c) {
      c.classList.remove("leaps-col-drag-ghost");
    });
    hideIndicator();
    // 拖曳結束後緊接著會發一個 click，會被 tooltips.js 當成「點表頭看說明」
    suppressNextClick = true;

    var insertAt = dropTargetIndex(d.tbl, e.clientX);
    var to = insertAt > d.index ? insertAt - 1 : insertAt;
    if (to === d.index) return;

    var before = currentOrder(d.tbl);
    moveColumn(d.tbl, d.index, to);
    persist(d.tbl, currentOrder(d.tbl), function () {
      // 還原：把目前順序搬回 before（逐欄搬到它該在的位置）
      before.forEach(function (key, target) {
        var from = currentOrder(d.tbl).indexOf(key);
        if (from !== -1 && from !== target) moveColumn(d.tbl, from, target);
      });
    });
  });

  document.addEventListener(
    "click",
    function (e) {
      if (!suppressNextClick) return;
      suppressNextClick = false;
      e.stopPropagation();
      e.preventDefault();
    },
    true,
  );
})();
