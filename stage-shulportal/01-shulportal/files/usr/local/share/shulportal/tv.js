// ABOUTME: Turns the TV's own pages on a TV hung sideways: shulportal-kiosk adds ?turn=right or ?turn=left from the
// ABOUTME: saved turn, and the page follows the turn helper as it changes (a pick on the phone during setup).
var root = document.documentElement;

function setTurn(turn) {
  if (turn === "right" || turn === "left") root.dataset.turn = turn;
  else delete root.dataset.turn;
}

setTurn(new URLSearchParams(location.search).get("turn"));

// The helper reads the same file the kiosk did; if it isn't running, the page keeps the turn it opened with.
setInterval(function () {
  fetch("http://127.0.0.1:8411/turn", { cache: "no-store" })
    .then(function (r) { return r.ok ? r.text() : Promise.reject(); })
    .then(function (turn) { setTurn(turn.trim()); })
    .catch(function () {});
}, 2000);
