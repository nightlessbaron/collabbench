(function () {
  "use strict";
  function playTitle(title) {
    return title.replace(/[^a-z0-9]+/gi, " ").trim().toLowerCase();
  }
  window.CREPlayer = { playTitle: playTitle };
})();
//# sourceMappingURL=player.js.map