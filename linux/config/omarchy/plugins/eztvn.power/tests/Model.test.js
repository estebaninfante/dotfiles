const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const states = {
  Charging: 1,
  Discharging: 2,
  FullyCharged: 4,
  PendingCharge: 5
}

test("parseKeyValue reads tab separated pairs", () => {
  const parsed = Model.parseKeyValue("percentage\t87%\nstate\tdischarging\n")
  assert.deepEqual(parsed, { percentage: "87%", state: "discharging" })
})

test("parseKeyValue ignores lines without a tab", () => {
  assert.deepEqual(Model.parseKeyValue("noise\ncpu\t23%\n"), { cpu: "23%" })
})

test("parseProfiles marks the active entry", () => {
  const parsed = Model.parseProfiles("power-saver\t0\nbalanced\t1\nperformance\t0\n", 0)
  assert.deepEqual(parsed.profiles, ["power-saver", "balanced", "performance"])
  assert.equal(parsed.activeProfile, "balanced")
  assert.equal(parsed.profileIndex, 0)
})

test("parseProfiles clamps a stale index", () => {
  assert.equal(Model.parseProfiles("balanced\t1\n", 9).profileIndex, 0)
})

test("selectProfileIndex stays inside the list", () => {
  assert.equal(Model.selectProfileIndex(0, -1, ["a", "b"]), 0)
  assert.equal(Model.selectProfileIndex(1, 1, ["a", "b"]), 1)
  assert.equal(Model.selectProfileIndex(0, 0, []), 0)
})

test("percentageText tolerates the percent suffix", () => {
  assert.equal(Model.percentageText("87%"), "87%")
  assert.equal(Model.percentageText(87), "87%")
  assert.equal(Model.percentageText(""), "—")
})

test("wattReadout distinguishes drain, charge and idle", () => {
  assert.equal(Model.wattReadout(12.4, 0), "12.4W")
  assert.equal(Model.wattReadout(0, 5.1), "+5.1W")
  assert.equal(Model.wattReadout(0, 0), "--.-W")
})

test("formatWatts fixes one decimal", () => {
  assert.equal(Model.formatWatts(12.44), "12.4W")
  assert.equal(Model.formatWatts(Number.NaN), "0.0W")
})

test("parseSample rejects empty payloads", () => {
  assert.equal(Model.parseSample(""), null)
  assert.deepEqual(Model.parseSample("1790375031 12.4 0.0"), { t: 1790375031, w: 12.4, c: 0 })
})

test("parseHistory skips idle samples", () => {
  const raw = "1 0.0 0.0\n2 12.0 0.0\n3 0.0 5.0\n"
  assert.deepEqual(Model.parseHistory(raw), [
    { t: 2, w: 12, c: 0 },
    { t: 3, w: 0, c: 5 }
  ])
})

test("parseHistory keeps the newest samples within the cap", () => {
  const raw = "1 1.0 0.0\n2 2.0 0.0\n3 3.0 0.0\n"
  assert.deepEqual(Model.parseHistory(raw, 2).map((s) => s.t), [2, 3])
})

test("computeStats averages and integrates discharge only", () => {
  const samples = [
    { t: 100, w: 10, c: 0 },
    { t: 110, w: 20, c: 0 },
    { t: 120, w: 0, c: 30 }
  ]
  const stats = Model.computeStats(samples, 10, 130)
  assert.equal(stats.average, 15)
  assert.equal(stats.peak, 20)
  assert.ok(Math.abs(stats.energyWh - 20 * 10 / 3600) < 1e-9)
})

test("computeStats drops stale samples outside the window", () => {
  const samples = [
    { t: 10, w: 50, c: 0 },
    { t: 1000, w: 10, c: 0 }
  ]
  const stats = Model.computeStats(samples, 5, 1000)
  assert.equal(stats.peak, 10)
})

test("computeTrend compares the newest draw against the oldest", () => {
  assert.equal(Model.computeTrend([{ t: 100, w: 5, c: 0 }, { t: 110, w: 9, c: 0 }], 10, 120), "↑")
  assert.equal(Model.computeTrend([{ t: 100, w: 9, c: 0 }, { t: 110, w: 5, c: 0 }], 10, 120), "↓")
  assert.equal(Model.computeTrend([], 10, 120), "→")
})

test("batteryIcon follows state and charge level", () => {
  assert.equal(Model.batteryIcon({ isPresent: false }, false, states), "")
  assert.equal(Model.batteryIcon({ isPresent: true, percentage: 1, state: states.FullyCharged }, false, states), "󰂅")
  assert.equal(Model.batteryIcon({ isPresent: true, percentage: 0.1, state: states.Discharging }, true, states), "󰁻")
})

test("chargeThresholdActive detects a held charge", () => {
  assert.equal(Model.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: states.PendingCharge }, false, states), true)
  assert.equal(Model.chargeThresholdActive({ isPresent: true, percentage: 0.5, state: states.Discharging }, true, states), false)
})

test("stateLabel maps upower states", () => {
  assert.equal(Model.stateLabel("fully-charged"), "Fully charged")
  assert.equal(Model.stateLabel("holding"), "Holding")
  assert.equal(Model.stateLabel(""), "—")
})

test("timeLabel hides the estimate while holding", () => {
  assert.equal(Model.timeLabel("holding", "1h 20m"), "—")
  assert.equal(Model.timeLabel("discharging", "1h 20m"), "1h 20m")
  assert.equal(Model.timeLabel("discharging", ""), "—")
})

test("runtimeEstimate divides remaining charge by average draw", () => {
  assert.equal(Model.runtimeEstimate({ size: "60Wh", percentage: "50%" }, 30, true), "1h 0m")
  assert.equal(Model.runtimeEstimate({ size: "60Wh", percentage: "50%" }, 30, false), "—")
  assert.equal(Model.runtimeEstimate({ size: "60Wh", percentage: "50%" }, 0, true), "—")
})

test("humanDuration renders hours and minutes", () => {
  assert.equal(Model.humanDuration(0.5), "30m")
  assert.equal(Model.humanDuration(2.5), "2h 30m")
  assert.equal(Model.humanDuration(-1), "—")
})

test("minutesLabel switches to hours past sixty", () => {
  assert.equal(Model.minutesLabel(10), "10m")
  assert.equal(Model.minutesLabel(180), "3h")
})

test("uptimeText formats seconds", () => {
  assert.equal(Model.uptimeText(16546), "4h 36m")
  assert.equal(Model.uptimeText(-1), "—")
})

test("temperatureText rounds and guards zero", () => {
  assert.equal(Model.temperatureText(68.4), "68°C")
  assert.equal(Model.temperatureText(0), "—")
})
