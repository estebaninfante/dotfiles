const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const now = 1791400000

function line(name, windows, attached, created, activity) {
  return [name, windows, attached, created, activity].join("\t")
}

test("parseSessions reads tab separated tmux rows", () => {
  const raw = [
    line("0", 1, 1, 1791394414, 1791397255),
    line("work", 3, 0, 1791395588, 1791400000)
  ].join("\n") + "\n"
  assert.deepEqual(Model.parseSessions(raw), [
    { name: "0", windows: 1, attached: true, created: 1791394414, activity: 1791397255 },
    { name: "work", windows: 3, attached: false, created: 1791395588, activity: 1791400000 }
  ])
})

test("parseSessions keeps session names that contain pipes", () => {
  const raw = line("a|b|c", 2, 0, 1, 2) + "\n"
  assert.equal(Model.parseSessions(raw)[0].name, "a|b|c")
})

test("parseSessions keeps session names that contain spaces", () => {
  const raw = line("my project", 1, 0, 1, 2) + "\n"
  assert.equal(Model.parseSessions(raw)[0].name, "my project")
})

test("parseSessions ignores empty output from a dead tmux server", () => {
  assert.deepEqual(Model.parseSessions(""), [])
  assert.deepEqual(Model.parseSessions("\n"), [])
  assert.deepEqual(Model.parseSessions(null), [])
})

test("parseSessions drops malformed rows", () => {
  assert.deepEqual(Model.parseSessions("no-server-running\n"), [])
  assert.deepEqual(Model.parseSessions(line("", 1, 0, 1, 2) + "\n"), [])
  assert.deepEqual(Model.parseSessions(line("ok", 1, 0, 1, 2) + "\nbroke\n"), [
    { name: "ok", windows: 1, attached: false, created: 1, activity: 2 }
  ])
})

test("parseSessions tolerates a trailing carriage return", () => {
  const raw = line("0", 1, 0, 1, 2) + "\r\n"
  assert.equal(Model.parseSessions(raw)[0].name, "0")
})

test("sameSessions compares by content", () => {
  const a = Model.parseSessions(line("0", 1, 0, 1, 2) + "\n")
  const b = Model.parseSessions(line("0", 1, 0, 1, 2) + "\n")
  assert.equal(Model.sameSessions(a, b), true)
  assert.equal(Model.sameSessions(a, []), false)
  assert.equal(Model.sameSessions(undefined, undefined), true)
})

test("ageText scales from minutes to days", () => {
  assert.equal(Model.ageText(0), "1 min")
  assert.equal(Model.ageText(59), "1 min")
  assert.equal(Model.ageText(60), "1 min")
  assert.equal(Model.ageText(180), "3 min")
  assert.equal(Model.ageText(3599), "59 min")
  assert.equal(Model.ageText(3600), "1 h")
  assert.equal(Model.ageText(86399), "23 h")
  assert.equal(Model.ageText(86400), "1 d")
  assert.equal(Model.ageText(172800), "2 d")
  assert.equal(Model.ageText(-10), "1 min")
})

test("rowMeta reports attachment as in use before idle age", () => {
  const attached = { name: "0", windows: 1, attached: true, created: 0, activity: 1 }
  assert.equal(Model.rowMeta(attached, now), "1 ventana · en uso")
  const idle = { name: "1", windows: 2, attached: false, created: 0, activity: now - 300 }
  assert.equal(Model.rowMeta(idle, now), "2 ventanas · inactiva 5 min")
  assert.equal(Model.rowMeta(null, now), "")
  const unknown = { name: "2", windows: 1, attached: false, created: 0, activity: 0 }
  assert.equal(Model.rowMeta(unknown, now), "1 ventana · sin actividad")
})

test("sessionText and windowText pick the right plural", () => {
  assert.equal(Model.sessionText(1), "1 sesión")
  assert.equal(Model.sessionText(2), "2 sesiones")
  assert.equal(Model.windowText(1), "1 ventana")
  assert.equal(Model.windowText(4), "4 ventanas")
  assert.equal(Model.windowText("3"), "3 ventanas")
})

test("barText always shows the glyph and the count when there are sessions", () => {
  assert.equal(Model.barText(0), Model.widgetGlyph)
  assert.equal(Model.barText(7), Model.widgetGlyph + " 7")
})

test("tooltipText describes the session count", () => {
  assert.equal(Model.tooltipText(0), "tmux · sin sesiones")
  assert.equal(Model.tooltipText(1), "tmux · 1 sesión")
  assert.equal(Model.tooltipText(3), "tmux · 3 sesiones")
})

test("attachCommand quotes the session name for the shell", () => {
  assert.equal(
    Model.attachCommand("0"),
    "omarchy launch terminal tmux attach -t '0'"
  )
  assert.equal(
    Model.attachCommand("my project"),
    "omarchy launch terminal tmux attach -t 'my project'"
  )
  assert.equal(
    Model.attachCommand("it's"),
    "omarchy launch terminal tmux attach -t 'it'\\''s'"
  )
  assert.equal(Model.attachCommand(""), "")
  assert.equal(Model.attachCommand(null), "")
})

test("shellQuote never lets a value escape its quotes", () => {
  assert.equal(Model.shellQuote("a b"), "'a b'")
  assert.equal(Model.shellQuote("$(id)"), "'$(id)'")
  assert.equal(Model.shellQuote("x'y"), "'x'\\''y'")
})

test("killSessionArgv passes the session name verbatim as argv", () => {
  assert.deepEqual(Model.killSessionArgv("0"), ["tmux", "kill-session", "-t", "0"])
  assert.deepEqual(Model.killSessionArgv("my project"), ["tmux", "kill-session", "-t", "my project"])
  assert.deepEqual(Model.killSessionArgv("it's"), ["tmux", "kill-session", "-t", "it's"])
  assert.deepEqual(Model.killSessionArgv("$(id)"), ["tmux", "kill-session", "-t", "$(id)"])
  assert.deepEqual(Model.killSessionArgv("-weird"), ["tmux", "kill-session", "-t", "-weird"])
  assert.deepEqual(Model.killSessionArgv("a\nb"), ["tmux", "kill-session", "-t", "a\nb"])
})

test("killSessionArgv refuses an empty target", () => {
  assert.deepEqual(Model.killSessionArgv(""), [])
  assert.deepEqual(Model.killSessionArgv(null), [])
  assert.deepEqual(Model.killSessionArgv(undefined), [])
})

test("killServerArgv is the whole-server kill", () => {
  assert.deepEqual(Model.killServerArgv(), ["tmux", "kill-server"])
})

test("sessionByName resolves a session by exact name", () => {
  const sessions = Model.parseSessions([line("0", 2, 1, 1, 2), line("1", 1, 0, 1, 2)].join("\n"))
  assert.equal(Model.sessionByName(sessions, "0").attached, true)
  assert.equal(Model.sessionByName(sessions, "1").windows, 1)
  assert.equal(Model.sessionByName(sessions, "2"), null)
  assert.equal(Model.sessionByName(sessions, null), null)
  assert.equal(Model.sessionByName(null, "0"), null)
  assert.equal(Model.sessionByName(undefined, "0"), null)
})

test("attachedNames lists only sessions someone is inside", () => {
  const sessions = Model.parseSessions([
    line("0", 1, 1, 1, 2),
    line("1", 1, 0, 1, 2),
    line("3", 2, 1, 1, 2)
  ].join("\n"))
  assert.deepEqual(Model.attachedNames(sessions), ["0", "3"])
  assert.deepEqual(Model.attachedNames([]), [])
  assert.deepEqual(Model.attachedNames(null), [])
})

test("killConfirmMessage states the damage of one session", () => {
  assert.equal(
    Model.killConfirmMessage({ name: "1", windows: 3, attached: false, created: 0, activity: 1 }),
    "¿Eliminar la sesión «1»? Se cierran sus 3 ventanas."
  )
  assert.equal(
    Model.killConfirmMessage({ name: "2", windows: 1, attached: false, created: 0, activity: 1 }),
    "¿Eliminar la sesión «2»? Se cierra su ventana."
  )
  assert.equal(
    Model.killConfirmMessage({ name: "3", windows: 0, attached: false, created: 0, activity: 1 }),
    "¿Eliminar la sesión «3»? No tiene ventanas abiertas."
  )
  assert.equal(Model.killConfirmMessage(null), "")
})

test("killConfirmMessage flags an attached session as in use", () => {
  assert.equal(
    Model.killConfirmMessage({ name: "0", windows: 1, attached: true, created: 0, activity: 1 }),
    "¿Eliminar la sesión «0»? Está ADJUNTADA: alguien trabaja ahí dentro. Se cierra su ventana."
  )
})

test("killConfirmSecond only demands a second step for attached sessions", () => {
  const attached = { name: "0", windows: 1, attached: true, created: 0, activity: 1 }
  const idle = { name: "1", windows: 1, attached: false, created: 0, activity: 1 }
  assert.equal(Model.killConfirmSecond(idle), "")
  assert.equal(Model.killConfirmSecond(null), "")
  assert.match(Model.killConfirmSecond(attached), /en uso/)
  assert.match(Model.killConfirmSecond(attached), /Última confirmación/)
  assert.match(Model.killConfirmSecond(attached), /«0»/)
})

test("killAllConfirmMessage counts every session and names the attached ones", () => {
  const sessions = Model.parseSessions([
    line("0", 1, 1, 1, 2),
    line("1", 1, 0, 1, 2),
    line("3", 2, 1, 1, 2)
  ].join("\n"))
  assert.equal(
    Model.killAllConfirmMessage(sessions),
    "¿Eliminar 3 sesiones de esta máquina? Adjuntas (en uso): 0, 3."
  )
  assert.equal(Model.killAllConfirmMessage([]), "")
  assert.equal(Model.killAllConfirmMessage(undefined), "")
})

test("killAllConfirmMessage says when nothing is attached", () => {
  const sessions = Model.parseSessions([line("1", 1, 0, 1, 2), line("2", 1, 0, 1, 2)].join("\n"))
  assert.equal(
    Model.killAllConfirmMessage(sessions),
    "¿Eliminar 2 sesiones de esta máquina? Ninguna está adjuntada."
  )
})

test("killAllConfirmSecond always demands a last confirmation", () => {
  const sessions = Model.parseSessions([
    line("0", 1, 1, 1, 2),
    line("1", 1, 0, 1, 2),
    line("3", 2, 1, 1, 2)
  ].join("\n"))
  const withAttached = Model.killAllConfirmSecond(sessions)
  assert.match(withAttached, /Última confirmación/)
  assert.match(withAttached, /0, 3/)
  assert.match(withAttached, /server de tmux/)
  const idleOnly = Model.killAllConfirmSecond(Model.parseSessions(line("1", 1, 0, 1, 2) + "\n"))
  assert.match(idleOnly, /Última confirmación/)
  assert.doesNotMatch(idleOnly, /pierden su trabajo/)
  assert.equal(Model.killAllConfirmSecond([]), "")
})
