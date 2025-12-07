/**
 * @license MIT
 * topbar 2.0.0, 2023-02-04
 * https://buunguyen.github.io/topbar
 * Copyright (c) 2021 Buu Nguyen
 */
(function (window, document) {
  "use strict";

  (function () {
    var lastTime = 0;
    var vendors = ["ms", "moz", "webkit", "o"];
    for (var x = 0; x < vendors.length && !window.requestAnimationFrame; ++x) {
      window.requestAnimationFrame =
        window[vendors[x] + "RequestAnimationFrame"];
      window.cancelAnimationFrame =
        window[vendors[x] + "CancelAnimationFrame"] ||
        window[vendors[x] + "CancelRequestAnimationFrame"];
    }
    if (!window.requestAnimationFrame)
      window.requestAnimationFrame = function (callback, element) {
        var currTime = new Date().getTime();
        var timeToCall = Math.max(0, 16 - (currTime - lastTime));
        var id = window.setTimeout(function () {
          callback(currTime + timeToCall);
        }, timeToCall);
        lastTime = currTime + timeToCall;
        return id;
      };
    if (!window.cancelAnimationFrame)
      window.cancelAnimationFrame = function (id) {
        clearTimeout(id);
      };
  })();

  var canvas,
    currentProgress,
    showing,
    progressTimerId = null,
    fadeTimerId = null,
    delayTimerId = null,
    addEvent = function (elem, type, handler) {
      if (elem.addEventListener) elem.addEventListener(type, handler, false);
      else if (elem.attachEvent) elem.attachEvent("on" + type, handler);
      else elem["on" + type] = handler;
    },
    options = {
      autoRun: true,
      barThickness: 2,
      barColors: {
        0: "rgba(255, 255, 255, 1)",
      },
      shadowBlur: 0,
      shadowColor: "rgba(0, 0, 0, 0)",
      className: null,
    },
    repaint = function () {
      canvas.width = window.innerWidth;
      canvas.height = options.barThickness;

      var ctx = canvas.getContext("2d");
      ctx.shadowBlur = options.shadowBlur;
      ctx.shadowColor = options.shadowColor;

      var stop,
        gradient = ctx.createLinearGradient(0, 0, canvas.width, 0);
      for (stop in options.barColors)
        gradient.addColorStop(stop, options.barColors[stop]);
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, Math.ceil(currentProgress * canvas.width), canvas.height);
    },
    createCanvas = function () {
      canvas = document.createElement("canvas");
      var style = canvas.style;
      style.position = "fixed";
      style.top = style.left = style.right = style.margin = style.padding = 0;
      style.zIndex = 100001;
      style.display = "none";
      if (options.className) canvas.classList.add(options.className);
      document.body.appendChild(canvas);
      addEvent(window, "resize", repaint);
    },
    topbar = {
      config: function (opts) {
        for (var key in opts)
          if (options.hasOwnProperty(key)) options[key] = opts[key];
      },
      show: function (delay) {
        if (showing) return;
        if (delay) {
          if (delayTimerId) return;
          delayTimerId = setTimeout(() => topbar.show(), delay);
        } else {
          showing = true;
          if (fadeTimerId !== null) window.cancelAnimationFrame(fadeTimerId);
          if (!canvas) createCanvas();
          canvas.style.opacity = 1;
          canvas.style.display = "block";
          topbar.progress(0);
          if (options.autoRun) {
            (function loop() {
              progressTimerId = window.requestAnimationFrame(loop);
              topbar.progress(
                "+" + 0.05 * Math.pow(1 - Math.sqrt(currentProgress), 2)
              );
            })();
          }
        }
      },
      progress: function (to) {
        if (typeof to === "undefined") return currentProgress;
        if (typeof to === "string") {
          to =
            (to.indexOf("+") >= 0 || to.indexOf("-") >= 0
              ? currentProgress
              : 0) + parseFloat(to);
        }
        currentProgress = to > 1 ? 1 : to;
        repaint();
        return currentProgress;
      },
      hide: function () {
        if (delayTimerId) {
          clearTimeout(delayTimerId);
          delayTimerId = null;
        }
        if (!showing) return;
        showing = false;
        if (progressTimerId != null) {
          window.cancelAnimationFrame(progressTimerId);
          progressTimerId = null;
        }
        (function loop() {
          if (topbar.progress("+0.1") >= 1) {
            canvas.style.opacity -= 0.05;
            if (canvas.style.opacity <= 0.05) {
              canvas.style.display = "none";
              fadeTimerId = null;
              return;
            }
          }
          fadeTimerId = window.requestAnimationFrame(loop);
        })();
      },
    };

  window.topbar = topbar;
})(window, document);

export default window.topbar;

