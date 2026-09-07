(function () {
  "use strict";

  var STORAGE_KEY = "enkapp-hero";
  var VARIANTS = ["phones", "terminal"];
  var sw = document.getElementById("heroSwitch");
  if (!sw) return;

  var buttons = Array.prototype.slice.call(sw.querySelectorAll(".hero-toggle-btn"));

  function readPreferred() {
    try {
      var q = new URLSearchParams(window.location.search).get("hero");
      if (VARIANTS.indexOf(q) !== -1) return q;
    } catch (e) {}
    if (window.location.hash === "#terminal") return "terminal";
    try {
      var stored = window.localStorage.getItem(STORAGE_KEY);
      if (VARIANTS.indexOf(stored) !== -1) return stored;
    } catch (e) {}
    return "phones";
  }

  function apply(variant, persist) {
    if (VARIANTS.indexOf(variant) === -1) variant = "phones";
    sw.setAttribute("data-hero", variant);
    buttons.forEach(function (btn) {
      btn.setAttribute("aria-selected", btn.getAttribute("data-hero-target") === variant ? "true" : "false");
    });
    if (persist) {
      try { window.localStorage.setItem(STORAGE_KEY, variant); } catch (e) {}
    }
  }

  buttons.forEach(function (btn) {
    btn.addEventListener("click", function () {
      apply(btn.getAttribute("data-hero-target"), true);
    });
  });

  apply(readPreferred(), false);

  /* Terminal demo animation */
  var rowsEl = document.getElementById("termRows");
  var typedEl = document.getElementById("termTyped");
  var timerEl = document.getElementById("termTimer");
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (rowsEl && typedEl && timerEl && !reduce) {
    var TARGET = "EN1207";
    var LABELS = ["сектор 1", "сектор 2", "сектор 3", "сектор 4", "сектор 5"];
    var BASE_CODES = ["EN841", "CLOCK", "— — —", "— — —", "— — —"];
    var step = 0;

    function render() {
      var solved = step > 12 ? 3 : 2;
      var typedLen = Math.min(TARGET.length, Math.max(0, step - 2));
      var html = "";
      for (var i = 0; i < 5; i++) {
        var code = i === 2 && step > 12 ? "EN1207" : BASE_CODES[i];
        var status = i < solved ? "ПРИНЯТ" : i === solved ? "ВВОД" : "ЖДЁМ";
        var cls = i < solved ? "is-ok" : i === solved ? "is-input" : "is-wait";
        html += '<div class="term-row"><span>' + LABELS[i] + "</span><code>" +
          code + '</code><b class="' + cls + '">' + status + "</b></div>";
      }
      rowsEl.innerHTML = html;
      typedEl.textContent = step > 12 ? "" : TARGET.slice(0, typedLen);
      var secs = 39 - (step % 40);
      timerEl.textContent = "до слива 52:" + (secs < 10 ? "0" + secs : secs);
      step = (step + 1) % 28;
    }

    render();
    setInterval(render, 420);
  }
})();
