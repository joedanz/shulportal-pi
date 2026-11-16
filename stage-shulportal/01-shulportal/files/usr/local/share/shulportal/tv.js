// ABOUTME: Turns the TV's own pages on a TV hung sideways: shulportal-kiosk adds ?turn=right or ?turn=left from the
// ABOUTME: saved turn. The setup page also calls followTurn, to turn as soon as a choice is tapped on the phone.
var root = document.documentElement;

function setTurn(turn) {
  if (turn === "right" || turn === "left") root.dataset.turn = turn;
  else delete root.dataset.turn;
}

setTurn(new URLSearchParams(location.search).get("turn"));

// The turn helper (running only while the setup page is up) reads the same file the kiosk did; if it can't be
// reached, the page keeps the turn it opened with.
function followTurn() {
  setInterval(function () {
    fetch("http://127.0.0.1:8411/turn", { cache: "no-store" })
      .then(function (r) { return r.ok ? r.text() : Promise.reject(); })
      .then(function (turn) { setTurn(turn.trim()); })
      .catch(function () {});
  }, 2000);
}
