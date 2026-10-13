const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const rawStatus = JSON.stringify({
  version: "0.1.0",
  commit: "abc1234",
  pairingUrl: "https://192.168.1.240:4443/?t=JoQ4s903m7xIPEZ2lQM12M5c",
  qrPath: "/home/eztvn/.cache/hypr-remote/pair.png",
  httpPort: 4001,
  https: { address: "192.168.1.240", port: 4443 },
  clients: 1,
  uptimeSec: 1234,
  devices: [
    { id: "cd6952fe8103", name: "iphone", paired: 1790619977342, seen: 1790622237524, connected: true },
    { id: "aa11bb22cc33", name: "iphone", paired: 1790610000000, seen: 1790620000000, connected: false },
    { id: "ff00ee11dd22", name: "iphone", paired: 1790600000000, seen: 1790615000000, connected: false },
    { id: "112233445566", name: "iphone", paired: 1790590000000, seen: 1790610000000, connected: false }
  ]
})

test("parseStatus keeps the documented /status shape", () => {
  const status = Model.parseStatus(rawStatus)
  assert.equal(status.running, true)
  assert.equal(status.unit, "")
  assert.equal(status.version, "0.1.0")
  assert.equal(status.commit, "abc1234")
  assert.equal(status.qrPath, "/home/eztvn/.cache/hypr-remote/pair.png")
  assert.equal(status.httpPort, 4001)
  assert.deepEqual(status.https, { address: "192.168.1.240", port: 4443 })
  assert.equal(status.clients, 1)
  assert.equal(status.uptimeSec, 1234)
  assert.equal(status.paired, 4)
  assert.equal(status.connected, 1)
  assert.equal(status.devices.length, 4)
})

test("parseStatus accepts the degraded payload from the status script", () => {
  const status = Model.parseStatus('{"running":false,"unit":"active"}')
  assert.equal(status.running, false)
  assert.equal(status.unit, "active")
  assert.equal(status.paired, 0)
  assert.equal(status.connected, 0)
  assert.equal(status.https, null)
})

test("parseStatus rejects payloads that are not hypr-remote state", () => {
  assert.equal(Model.parseStatus(""), null)
  assert.equal(Model.parseStatus("not json"), null)
  assert.equal(Model.parseStatus("null"), null)
  assert.equal(Model.parseStatus('{"hello":"world"}'), null)
})

test("parseStatus tolerates a null https and a null commit", () => {
  const status = Model.parseStatus(JSON.stringify({ version: "0.2.0", commit: null, https: null, devices: null }))
  assert.equal(status.https, null)
  assert.equal(status.commit, "")
  assert.equal(status.paired, 0)
})

test("parseStatus drops device entries without an id", () => {
  const status = Model.parseStatus(JSON.stringify({
    devices: [{ id: "a", connected: false }, { name: "ghost" }, "junk"]
  }))
  assert.equal(status.paired, 1)
  assert.equal(status.devices[0].id, "a")
})

test("normalizeDevice keeps timestamps when the input is already normalized", () => {
  const once = Model.normalizeDevice({ id: "a", name: "iphone", paired: 1700, seen: 1900, connected: true })
  const twice = Model.normalizeDevice(once)
  assert.deepEqual(twice, once)
  assert.equal(twice.pairedAt, 1700)
  assert.equal(twice.seenAt, 1900)
})

test("kind tracks connection and liveness", () => {
  const up = Model.parseStatus(rawStatus)
  assert.equal(Model.kind(up), "active")
  assert.equal(Model.kind(Model.parseStatus('{"running":false}')), "down")
  assert.equal(Model.kind(null), "down")
  const idle = JSON.parse(rawStatus)
  idle.devices = idle.devices.map((d) => ({ ...d, connected: false }))
  assert.equal(Model.kind(Model.parseStatus(JSON.stringify(idle))), "idle")
})

test("barText shows connected/paired only while the socket answers", () => {
  assert.equal(Model.barText(Model.parseStatus(rawStatus)), "󰄜 1/4")
  assert.equal(Model.barText(Model.parseStatus('{"running":false,"unit":"active"}')), "󰄜")
  assert.equal(Model.barText(null), "󰄜")
  assert.equal(Model.barText(Model.parseStatus(JSON.stringify({ devices: [] }))), "󰄜")
})

test("summaryText reads down, degraded and live states", () => {
  assert.equal(Model.summaryText(null), "hypr-remote sin datos")
  assert.equal(Model.summaryText(Model.parseStatus('{"running":false}')), "hypr-remote detenido")
  assert.equal(Model.summaryText(Model.parseStatus('{"running":false,"unit":"active"}')), "hypr-remote sin API de control")
  assert.equal(Model.summaryText(Model.parseStatus(rawStatus)), "hypr-remote · 1 conectado · 4 emparejados")
})

test("stateLabel separates stopped from control-less", () => {
  assert.equal(Model.stateLabel(null), "Sin datos")
  assert.equal(Model.stateLabel(Model.parseStatus(rawStatus)), "Corriendo")
  assert.equal(Model.stateLabel(Model.parseStatus('{"running":false,"unit":"active"}')), "Sin API de control")
  assert.equal(Model.stateLabel(Model.parseStatus('{"running":false,"unit":"inactive"}')), "Detenido")
})

test("unitActive is true when the socket answers or the unit is up", () => {
  assert.equal(Model.unitActive(Model.parseStatus(rawStatus)), true)
  assert.equal(Model.unitActive(Model.parseStatus('{"running":false,"unit":"active"}')), true)
  assert.equal(Model.unitActive(Model.parseStatus('{"running":false,"unit":"inactive"}')), false)
  assert.equal(Model.unitActive(null), false)
})

test("unitState implies active from a live socket and keeps the degraded field", () => {
  assert.equal(Model.unitState(Model.parseStatus(rawStatus)), "active")
  assert.equal(Model.unitState(Model.parseStatus('{"running":false,"unit":"active"}')), "active")
  assert.equal(Model.unitState(Model.parseStatus('{"running":false,"unit":"failed"}')), "failed")
  assert.equal(Model.unitState(Model.parseStatus('{"running":false}')), "unknown")
  assert.equal(Model.unitState(null), "—")
})

test("uptimeText formats seconds, minutes, hours and days", () => {
  assert.equal(Model.uptimeText(-1), "—")
  assert.equal(Model.uptimeText(42), "42 s")
  assert.equal(Model.uptimeText(600), "10 min")
  assert.equal(Model.uptimeText(7404), "2 h 3 min")
  assert.equal(Model.uptimeText(90000), "1 d 1 h")
})

test("ageText and relativeText bracket the thresholds", () => {
  assert.equal(Model.ageText(5000), "ahora mismo")
  assert.equal(Model.ageText(46000), "ahora mismo")
  assert.equal(Model.ageText(60000), "hace 1 min")
  assert.equal(Model.ageText(4000000), "hace 1 h")
  assert.equal(Model.ageText(200000000), "hace 2 d")
  assert.equal(Model.relativeText(0, 1000), "—")
  assert.equal(Model.relativeText(1000, 0), "—")
  assert.equal(Model.relativeText(1000, 61000), "hace 1 min")
})

test("httpsText and versionText degrade gracefully", () => {
  assert.equal(Model.httpsText(null), "—")
  assert.equal(Model.httpsText(Model.parseStatus('{"running":false}')), "—")
  assert.equal(Model.httpsText(Model.parseStatus(JSON.stringify({ https: null }))), "desactivado")
  assert.equal(Model.httpsText(Model.parseStatus(rawStatus)), "192.168.1.240:4443")
  assert.equal(Model.versionText(Model.parseStatus(rawStatus)), "0.1.0 (abc1234)")
  assert.equal(Model.versionText(Model.parseStatus(JSON.stringify({ version: "0.1.0" }))), "0.1.0")
  assert.equal(Model.versionText(Model.parseStatus('{"running":false}')), "—")
})

test("deviceRows sorts connected phones first and labels the ages", () => {
  const now = 1790623000000
  const rows = Model.deviceRows(Model.parseStatus(rawStatus).devices, now)
  assert.equal(rows.length, 4)
  assert.equal(rows[0].id, "cd6952fe8103")
  assert.equal(rows[0].connected, true)
  assert.equal(rows[0].seenText, "conectado ahora")
  assert.equal(rows[0].pairedText, "hace 50 min")
  assert.equal(rows[1].connected, false)
  assert.equal(rows[1].name, "iphone")
  assert.deepEqual(Model.deviceRows(null, now), [])
})

test("deviceRows names anonymous phones", () => {
  const rows = Model.deviceRows([{ id: "x", pairedAt: 0, seenAt: 0, connected: false }], 1000)
  assert.equal(rows[0].name, "teléfono")
  assert.equal(rows[0].pairedText, "—")
  assert.equal(rows[0].seenText, "—")
})

test("addressText surfaces the pairing url", () => {
  assert.equal(Model.addressText(Model.parseStatus(rawStatus)), "https://192.168.1.240:4443/?t=JoQ4s903m7xIPEZ2lQM12M5c")
  assert.equal(Model.addressText(Model.parseStatus('{"running":false}')), "—")
})

test("widgetGlyph is the cellphone mark", () => {
  assert.equal(Model.widgetGlyph, "󰄜")
})
