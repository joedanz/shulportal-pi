// ABOUTME: Turns the TV's own pages on a TV hung sideways: shulportal-kiosk adds ?turn=right or ?turn=left,
// ABOUTME: from how ShulPortal says the sign hangs, and tv.css turns the page to match.
var turn = new URLSearchParams(location.search).get("turn");
if (turn === "right" || turn === "left") document.documentElement.dataset.turn = turn;
