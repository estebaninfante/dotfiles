// Page registry and navigation for the dashboard panel. Kept pure and
// QML-free so the ordering rules can be unit tested under node and so the
// panel, header, and index page all read one source of truth.

// Canonical page order. `menu` is the index page: it is a destination but
// deliberately sits outside the prev/next ring, so cycling never lands on the
// table of contents — you go there by clicking the title.
var PAGES = [
  {
    id: "calendar",
    title: "Calendario",
    glyph: "󰃭",
    description: "Mes, progreso del año y memento mori"
  },
  {
    id: "system",
    title: "Sistema",
    glyph: "󰍹",
    description: "CPU, memoria, disco, temperatura y uptime"
  },
  {
    id: "media",
    title: "Media",
    glyph: "󰎆",
    description: "Reproducción actual con carátula y controles"
  },
  {
    id: "notifications",
    title: "Notificaciones",
    glyph: "󰂚",
    description: "Historial de notificaciones recientes"
  },
  {
    id: "toggles",
    title: "Toggles",
    glyph: "󰒓",
    description: "Wi-Fi, Bluetooth, audio, brillo y luz nocturna"
  },
  {
    id: "menu",
    title: "Menú",
    glyph: "󰍜",
    description: "Todas las páginas",
    indexOnly: true
  }
]

var DEFAULT_PAGE = "calendar"

function allPages() {
  return PAGES.slice()
}

function navPages() {
  var out = []
  for (var i = 0; i < PAGES.length; i++)
    if (!PAGES[i].indexOnly) out.push(PAGES[i])
  return out
}

function pageById(id) {
  var needle = String(id === undefined || id === null ? "" : id)
  for (var i = 0; i < PAGES.length; i++)
    if (PAGES[i].id === needle) return PAGES[i]
  return null
}

function isValid(id) {
  return pageById(id) !== null
}

// Unknown or missing ids fall back to the default page rather than throwing,
// so a hand-edited state file can never leave the panel blank.
function normalize(id) {
  return isValid(id) ? String(id) : DEFAULT_PAGE
}

function title(id) {
  var page = pageById(normalize(id))
  return page ? page.title : DEFAULT_PAGE
}

// Prev/next over the ring only. From the index page, stepping forward lands
// on the first entry and stepping back on the last, so the arrows always do
// something sensible.
function stepPage(id, delta) {
  var ring = navPages()
  if (ring.length === 0) return DEFAULT_PAGE
  var step = Number(delta) || 0
  var current = normalize(id)
  for (var i = 0; i < ring.length; i++) {
    if (ring[i].id === current) {
      var next = (i + step) % ring.length
      if (next < 0) next += ring.length
      return ring[next].id
    }
  }
  return step >= 0 ? ring[0].id : ring[ring.length - 1].id
}

function navIndex(id) {
  var ring = navPages()
  var current = normalize(id)
  for (var i = 0; i < ring.length; i++)
    if (ring[i].id === current) return i
  return -1
}

function navCount() {
  return navPages().length
}

// Page id -> QML file under pages/. Kept here so the panel never builds a
// path from user-controlled text.
var FILE_BY_ID = {
  calendar: "CalendarPage.qml",
  system: "SystemPage.qml",
  media: "MediaPage.qml",
  notifications: "NotificationsPage.qml",
  toggles: "TogglesPage.qml",
  menu: "MenuPage.qml"
}

function file(id) {
  return FILE_BY_ID[normalize(id)] || FILE_BY_ID[DEFAULT_PAGE]
}

// Short relative age for notification rows.
function relativeAge(timestamp, now) {
  var then = Number(timestamp)
  if (!isFinite(then)) return ""
  var seconds = Math.max(0, Math.round((Number(now) - then) / 1000))
  if (seconds < 60) return "ahora"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  return days + "d"
}

// Format seconds as m:ss / h:mm:ss for media position readouts.
function formatClock(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var secs = total % 60
  function pad(n) { return (n < 10 ? "0" : "") + n }
  if (hours > 0) return hours + ":" + pad(minutes) + ":" + pad(secs)
  return minutes + ":" + pad(secs)
}

if (typeof module !== "undefined") {
  module.exports = {
    PAGES: PAGES,
    DEFAULT_PAGE: DEFAULT_PAGE,
    allPages: allPages,
    navPages: navPages,
    pageById: pageById,
    isValid: isValid,
    normalize: normalize,
    title: title,
    stepPage: stepPage,
    navIndex: navIndex,
    navCount: navCount,
    file: file,
    relativeAge: relativeAge,
    formatClock: formatClock
  }
}
