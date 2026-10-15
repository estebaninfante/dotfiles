const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")
const Topology = require("../../io.github.dragosol.better-displays-pro/TopologyModel.js")

const LIST = "id 0: 192.168.1.240:4242 (left) active: true, ips: {192.168.1.240}\n"

const MONITOR = {
  id: 0,
  name: "DP-2",
  make: "ASUSTek COMPUTER INC.",
  model: "VG27AQL3A",
  description: "ASUSTek COMPUTER INC. VG27AQL3A 00000001",
  width: 2560,
  height: 1440,
  refreshRate: 59.951,
  x: 0,
  y: 0,
  scale: 1.25,
  transform: 0,
  focused: true,
  activeWorkspace: { id: 1 },
  disabled: false
}

const PEER = Object.assign(Model.peerDisplay("192.168.1.240"), { position: "left" })

test("parseList reads the daemon line", () => {
  const parsed = Model.parseList(LIST)
  assert.equal(parsed.ok, true)
  assert.equal(parsed.clients.length, 1)
  assert.deepEqual(parsed.clients[0], {
    id: "0",
    host: "192.168.1.240",
    port: "4242",
    position: "left",
    active: true,
    ips: ["192.168.1.240"],
    source: "daemon"
  })
})

test("parseList ignores non-CLI output", () => {
  assert.deepEqual(Model.parseList("error: socket busy\n").clients, [])
})

test("parseConfigClients falls back to config.toml", () => {
  const toml = [
    "[general]",
    "port = 4242",
    "",
    "[[clients]]",
    'hostname = "192.168.1.240"',
    'position = "right"',
    'ips = ["192.168.1.240"]',
    ""
  ].join("\n")
  const clients = Model.parseConfigClients(toml)
  assert.equal(clients.length, 1)
  assert.equal(clients[0].host, "192.168.1.240")
  assert.equal(clients[0].port, "")
  assert.equal(clients[0].position, "right")
  assert.equal(clients[0].source, "config")
})

const IP_JSON = JSON.stringify([
  {
    ifindex: 1, ifname: "lo", addr_info: [
      { family: "inet", local: "127.0.0.1", scope: "host" }
    ]
  },
  {
    ifindex: 2, ifname: "enp9s0", addr_info: [
      { family: "inet6", local: "fe80::1", scope: "link" },
      { family: "inet", local: "192.168.1.241", prefixlen: 24, scope: "global" }
    ]
  }
])

test("firstLocalIp reads global IPv4 addresses from ip -j", () => {
  assert.equal(Model.firstLocalIp(IP_JSON), "192.168.1.241")
  assert.deepEqual(Model.parseLocalIps("not json"), [])
  assert.deepEqual(Model.parseLocalIps("[]"), [])
  assert.equal(Model.firstLocalIp("{}"), "")
})

test("argv builders match the lan-mouse CLI", () => {
  assert.deepEqual(Model.setPositionArgs("0", "right"),
    ["lan-mouse", "cli", "set-position", "0", "right"])
  assert.deepEqual(Model.setActiveArgs("0", true),
    ["lan-mouse", "cli", "activate", "0"])
  assert.deepEqual(Model.setActiveArgs("0", false),
    ["lan-mouse", "cli", "deactivate", "0"])
  assert.deepEqual(Model.saveConfigArgs(), ["lan-mouse", "cli", "save-config"])
})

test("localDisplay uses logical size and picks the focused monitor", () => {
  const blurred = Object.assign({}, MONITOR, { focused: false })
  const display = Model.localDisplay([blurred, MONITOR])
  assert.equal(display.key, "DP-2")
  assert.equal(display.logicalWidth, 2048)
  assert.equal(display.logicalHeight, 1152)
  assert.match(display.sublabel, /DP-2/)
  assert.equal(Model.localDisplay([]), null)
})

test("logicalRects seats peers on each side of the local display", () => {
  const rects = Model.logicalRects(Model.localDisplay([MONITOR]), [PEER], 24)
  assert.equal(rects.local.width, 2048)
  assert.equal(rects.peers["192.168.1.240"].x, -24 - 1920)
  assert.equal(rects.peers["192.168.1.240"].y, (1152 - 1080) / 2)
})

test("fitLayout scales the group into the canvas", () => {
  const fit = Model.fitLayout(Model.localDisplay([MONITOR]), [PEER], 360, 210, 14, 0.92, 24)
  assert.ok(fit)
  assert.ok(fit.scale > 0 && fit.scale < 1)
  assert.ok(fit.local.x >= 14 - 0.01)
  assert.ok(fit.peers[0].x < fit.local.x)
  assert.ok(fit.peers[0].width + fit.peers[0].x >= 14 - 0.01)
  assert.equal(Model.fitLayout(null, [PEER], 360, 210, 14, 0.92, 24), null)
  assert.equal(Model.fitLayout(Model.localDisplay([MONITOR]), [PEER], 0, 0, 14, 0.92, 24), null)
})

test("peerCandidateRect shows where a zone would seat the peer", () => {
  const fit = Model.fitLayout(Model.localDisplay([MONITOR]), [PEER], 360, 210, 14, 0.92, 24)
  const key = PEER.key
  const left = Model.peerCandidateRect(fit, key, "left")
  const right = Model.peerCandidateRect(fit, key, "right")
  assert.ok(left.x < fit.local.x)
  assert.ok(right.x > fit.local.x + fit.local.width)
  assert.equal(left.width, right.width)
  assert.equal(Model.peerCandidateRect(fit, "missing", "left"), null)
})

test("zoneForPoint maps the drag center to a side", () => {
  const fit = Model.fitLayout(Model.localDisplay([MONITOR]), [PEER], 360, 210, 14, 0.92, 24)
  const local = fit.local
  const centerY = local.y + local.height / 2
  assert.equal(Model.zoneForPoint(fit, local.x - 1, centerY, "right"), "left")
  assert.equal(Model.zoneForPoint(fit, local.x + local.width + 1, centerY, "left"), "right")
  assert.equal(Model.zoneForPoint(fit, local.x + local.width / 2, local.y - 1, "left"), "top")
  assert.equal(Model.zoneForPoint(fit, local.x + local.width / 2, local.y + local.height + 1, "top"), "bottom")
  assert.equal(Model.zoneForPoint(fit, local.x + local.width / 2, centerY, "left"), "left")
  assert.equal(Model.zoneForPoint(null, 0, 0, "bottom"), "bottom")
})

test("planLocalExtend refuses to act without monitors", () => {
  const plan = Model.planLocalExtend([], Topology)
  assert.equal(plan.valid, false)
  assert.equal(plan.changed, false)
  assert.match(plan.reason, /monitores/)
})

test("planLocalExtend is a no-op for a single monitor", () => {
  const single = Object.assign({}, MONITOR, { x: 512, y: 128 })
  const plan = Model.planLocalExtend([single], Topology)
  assert.equal(plan.valid, true)
  assert.equal(plan.changed, false)
  assert.equal(plan.anchor, "DP-2")
  assert.equal(plan.originScreen, "DP-2")
  assert.equal(plan.originWorkspace, 1)
})

test("planLocalExtend aligns two monitors into one row in spatial order", () => {
  const left = Object.assign({}, MONITOR, { name: "DP-2", x: 0, y: 120, focused: true })
  const right = {
    id: 1, name: "HDMI-A-1", make: "Dell Inc.", model: "U2419H",
    width: 1920, height: 1080, refreshRate: 60, x: 2560, y: 0,
    scale: 1, transform: 0, focused: false, activeWorkspace: { id: 3 }
  }
  const plan = Model.planLocalExtend([right, left], Topology)
  assert.equal(plan.valid, true)
  assert.equal(plan.changed, true)
  assert.deepEqual(plan.proposed.map(d => d.name), ["DP-2", "HDMI-A-1"])
  assert.deepEqual(plan.proposed.map(d => d.y), [0, 0])
  assert.equal(plan.proposed[1].x, 2048)
  assert.equal(plan.proposed[1].refreshRate, 60)
  assert.equal(plan.anchor, "DP-2")
})

test("planLocalExtend is a no-op once the row is already aligned", () => {
  const left = Object.assign({}, MONITOR, { name: "DP-2", x: 0, y: 0, focused: true })
  const right = {
    id: 1, name: "HDMI-A-1", make: "Dell Inc.", model: "U2419H",
    width: 1920, height: 1080, refreshRate: 60, x: 2048, y: 0,
    scale: 1, transform: 0, focused: false, activeWorkspace: { id: 3 }
  }
  const plan = Model.planLocalExtend([left, right], Topology)
  assert.equal(plan.valid, true)
  assert.equal(plan.changed, false)
})
