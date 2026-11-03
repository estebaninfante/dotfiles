.pragma library

// mm:ss (minutes are not wrapped at 60, so a two-hour timer reads 120:00).
function clock(ms) {
  var total = Math.max(0, Math.ceil(Number(ms || 0) / 1000))
  var minutes = Math.floor(total / 60)
  var seconds = total % 60
  return minutes + ":" + (seconds < 10 ? "0" + seconds : String(seconds))
}
