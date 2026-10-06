import { createRequire } from "node:module";
import { readFileSync } from "node:fs";

function loadPlaywright() {
  try {
    return createRequire(import.meta.url)("playwright");
  } catch {
    return createRequire("/home/eztvn/.config/opencode/skills/browser-bench/bench/")("playwright");
  }
}

function pageProbe() {
  const issues = [];
  const add = (type, severity, detail, fix) => issues.push({ type, severity, detail, fix });
  const rct = (el) => el.getBoundingClientRect();
  const txt = (el) => (el.innerText || "").trim();
  const vis = (el) => {
    const s = getComputedStyle(el);
    const r = rct(el);
    return r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none" && parseFloat(s.opacity) > 0.05;
  };
  const els = [...document.querySelectorAll("body *")].filter(vis);

  const surfaces = els.filter((el) => {
    const s = getComputedStyle(el);
    const r = rct(el);
    const radius = parseFloat(s.borderTopLeftRadius) || 0;
    const hasBg = s.backgroundColor !== "rgba(0, 0, 0, 0)" && s.backgroundColor !== "transparent";
    const hasBorder = parseFloat(s.borderTopWidth) > 0;
    return radius >= 4 && (hasBg || hasBorder) && r.width >= 96 && r.height >= 28;
  });

  let padN = 0;
  let emptyN = 0;
  surfaces.forEach((el) => {
    const r = rct(el);
    const area = r.width * r.height;
    const leafs = [...el.querySelectorAll("*")].filter((k) => k.children.length === 0 && txt(k).length > 0 && vis(k));
    if (!leafs.length) return;
    let minL = Infinity;
    let minT = Infinity;
    let minR = Infinity;
    let minB = Infinity;
    let x0 = Infinity;
    let y0 = Infinity;
    let x1 = 0;
    let y1 = 0;
    for (const k of leafs) {
      const kr = rct(k);
      minL = Math.min(minL, kr.left - r.left);
      minT = Math.min(minT, kr.top - r.top);
      minR = Math.min(minR, r.right - kr.right);
      minB = Math.min(minB, r.bottom - kr.bottom);
      x0 = Math.min(x0, kr.left);
      y0 = Math.min(y0, kr.top);
      x1 = Math.max(x1, kr.right);
      y1 = Math.max(y1, kr.bottom);
    }
    const minPad = Math.min(minL, minT, minR, minB);
    if (minPad < 8 && padN < 8) {
      padN += 1;
      add("content-flush", "error", `superficie ${Math.round(r.width)}x${Math.round(r.height)}px con padding interno minimo ${Math.round(minPad)}px`, "padding interno >= 16px, simetrico en los 4 lados");
    }
    const textArea = Math.max(0, x1 - x0) * Math.max(0, y1 - y0);
    const ratio = area > 0 ? textArea / area : 0;
    const textLen = txt(el).length;
    if (area >= 30000 && textLen <= 24 && ratio < 0.06 && emptyN < 6) {
      emptyN += 1;
      add("empty-box", "error", `caja ${Math.round(r.width)}x${Math.round(r.height)}px con ${textLen} caracteres y fill ${(ratio * 100).toFixed(0)}% (casi vacia)`, "achicar la caja o agrandar/subir la info; un valor suelto no merece una caja enorme");
    }
  });

  let misN = 0;
  els.forEach((el) => {
    if (misN >= 5) return;
    const kids = [...el.children].filter(vis);
    if (kids.length < 3) return;
    const rowLeft = new Map();
    for (const k of kids) {
      const kr = rct(k);
      if (kr.width < 24 || kr.height < 8) continue;
      const key = Math.round(kr.top / 8);
      const cur = rowLeft.get(key);
      rowLeft.set(key, cur === undefined ? kr.left : Math.min(cur, kr.left));
    }
    if (rowLeft.size < 2) return;
    const lefts = [...rowLeft.values()];
    const mn = Math.min(...lefts);
    const mx = Math.max(...lefts);
    if (mx - mn > 6) {
      misN += 1;
      const cls = el.className.toString().slice(0, 40);
      add("misaligned", "warn", `bloque '${cls}' con ${rowLeft.size} filas apiladas y ejes izquierdos desalineados (min ${Math.round(mn)}px, max ${Math.round(mx)}px)`, "un unico eje horizontal para las filas apiladas de una columna");
    }
  });

  const fontSizes = new Set(
    els.filter((el) => txt(el).length > 0 && el.children.length === 0).map((el) => Math.round(parseFloat(getComputedStyle(el).fontSize)))
  );
  if (fontSizes.size > 6) {
    add("font-scale", "warn", `${fontSizes.size} tamanos de fuente distintos (${[...fontSizes].sort((a, b) => a - b).join(",")}px)`, "escala modular de <= 5 tamanos");
  }

  const targets = els.filter((el) => /^(A|BUTTON)$/.test(el.tagName) || getComputedStyle(el).cursor === "pointer");
  const small = targets.filter((el) => {
    const r = rct(el);
    return r.width > 0 && r.height > 0 && (r.height < 30 || r.width < 30);
  });
  if (small.length) add("small-target", "warn", `${small.length} area(s) clickeable(s) < 30px`, "targets >= 32px");

  const hues = new Set();
  const hueOf = (col) => {
    const m = col.match(/\d+/g);
    if (!m || m.length < 3) return;
    const [r, g, b] = m.map(Number);
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    if (max - min < 40 || max < 90) return;
    let h = 0;
    if (max === r) h = ((g - b) / (max - min)) % 6;
    else if (max === g) h = (b - r) / (max - min) + 2;
    else h = (r - g) / (max - min) + 4;
    hues.add(Math.round((((h * 60) % 360 + 360) % 360) / 45) * 45);
  };
  els.slice(0, 4000).forEach((el) => {
    const s = getComputedStyle(el);
    hueOf(s.color);
    hueOf(s.backgroundColor);
  });
  if (hues.size > 5) add("too-many-colors", "warn", `${hues.size} familias de color saturadas detectadas`, "paleta neutra + 1 acento; color solo con proposito");

  return { issues, metrics: { surfaces: surfaces.length, elements: els.length, fontSizes: fontSizes.size, hues: hues.size } };
}

const WEIGHT = {
  "content-flush": 1.6,
  "empty-box": 1.4,
  "too-many-colors": 1.2,
  misaligned: 0.8,
  "font-scale": 0.6,
  "small-target": 0.6,
};

function scoreOf(issues) {
  const penalty = issues.reduce((sum, it) => sum + (WEIGHT[it.type] || 0.5), 0);
  return Math.max(0, Math.min(10, Math.round((10 - penalty) * 10) / 10));
}

function report(url, result) {
  const score = scoreOf(result.issues);
  const rank = { error: 0, warn: 1, info: 2 };
  const sorted = [...result.issues].sort((a, b) => rank[a.severity] - rank[b.severity]);
  console.log(`Score: ${score.toFixed(1)}/10  ${score >= 8 ? "APROBADO" : "REDISEÑAR"}   (${url})`);
  console.log(`metricas: ${JSON.stringify(result.metrics)}`);
  if (!sorted.length) {
    console.log("Sin defectos detectados por el probe.");
    return;
  }
  console.log("Peores 3:");
  sorted.slice(0, 3).forEach((it) => console.log(`- ${it.type}: ${it.detail}. Fix: ${it.fix}`));
  console.log("Findings:");
  sorted.forEach((it) => console.log(`- [${it.severity}] ${it.type}: ${it.detail}. Fix: ${it.fix}`));
}

const SELFTEST_DIRTY = `<!doctype html><html><body style="margin:0;font-family:sans-serif">
<div style="width:600px;height:120px;background:#222;border-radius:8px;padding:0"><span style="color:#eee;font-size:30px;padding:0">23</span></div>
<div style="width:600px;height:220px;background:#222;border-radius:8px;padding:18px"><span style="color:#eee;font-size:30px">0</span></div>
<div style="width:500px;height:100px;background:#2a2a2a;border-radius:8px;padding:16px"><span style="color:#eee;font-size:24px">23</span><span style="color:#aaa;font-size:10px">NOTAS</span></div>
<div style="display:flex;gap:10px">
<div style="width:280px;height:60px;background:#333;border-radius:8px;padding:16px"><span style="color:#eee;font-size:14px">uno</span></div>
<div style="width:280px;height:60px;background:#333;border-radius:8px;padding:16px;margin-left:24px"><span style="color:#f00;font-size:20px">dos</span></div>
<div style="width:280px;height:60px;background:#333;border-radius:8px;padding:16px"><span style="color:#0f0;font-size:11px">tres</span></div>
</div>
<div style="font-size:7px;color:#0af;padding:4px">a</div>
<div style="font-size:40px;color:#0af;padding:4px">b</div>
<span style="font-size:9px;color:#0af">c</span>
<button style="width:20px;height:20px">x</button>
</body></html>`;

const SELFTEST_CLEAN = `<!doctype html><html><body style="margin:0;font-family:sans-serif;background:#1e1e2e">
<div style="display:flex;gap:16px;padding:0">
<div style="width:180px;height:64px;background:#181825;border-radius:12px;padding:16px"><span style="display:block;color:#cdd6f4;font-size:24px">23</span><span style="color:#a6adc8;font-size:11px">NOTAS</span></div>
<div style="width:180px;height:64px;background:#181825;border-radius:12px;padding:16px"><span style="display:block;color:#cdd6f4;font-size:24px">20</span><span style="color:#a6adc8;font-size:11px">PENDIENTES</span></div>
</div>
<div style="width:320px;height:150px;background:#181825;border-radius:12px;padding:20px;margin-top:16px">
<span style="display:block;color:#cdd6f4;font-size:16px">Titulo de la nota de ejemplo</span>
<span style="display:block;color:#a6adc8;font-size:13px;margin-top:6px">Cuerpo de la nota que ocupa varias lineas de texto real para llenar la tarjeta</span>
<span style="display:block;color:#a6adc8;font-size:11px;margin-top:10px">#tag #otro</span>
</div>
</body></html>`;

async function runProbe(page) {
  return page.evaluate(pageProbe);
}

async function selftest() {
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.setContent(SELFTEST_DIRTY, { waitUntil: "load" });
  const dirty = await runProbe(page);
  await page.setContent(SELFTEST_CLEAN, { waitUntil: "load" });
  const clean = await runProbe(page);
  await browser.close();

  const got = new Set(dirty.issues.map((i) => i.type));
  const need = ["content-flush", "empty-box", "font-scale", "small-target"];
  const missing = need.filter((t) => !got.has(t));
  const badClean = clean.issues.filter((i) => i.type === "content-flush" || i.type === "empty-box");
  const ok = missing.length === 0 && badClean.length === 0;
  console.log(JSON.stringify({ ok, dirtyTypes: [...got].sort(), missing, cleanFalsePositives: badClean.length }, null, 2));
  return ok;
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes("--selftest")) {
    const ok = await selftest();
    process.exit(ok ? 0 : 1);
  }
  const url = argv.find((a) => !a.startsWith("--"));
  if (!url) {
    console.error("uso: node probe.mjs <url> [--viewport WxH] [--wait ms] [--json] | --selftest");
    process.exit(2);
  }
  const vpIdx = argv.indexOf("--viewport");
  const waitIdx = argv.indexOf("--wait");
  const initIdx = argv.indexOf("--init");
  const shotIdx = argv.indexOf("--shot");
  const viewport = vpIdx >= 0 && argv[vpIdx + 1] ? argv[vpIdx + 1].split("x").map(Number) : [1440, 900];
  const waitMs = waitIdx >= 0 && argv[waitIdx + 1] ? Number(argv[waitIdx + 1]) : 1800;
  const initFile = initIdx >= 0 ? argv[initIdx + 1] : null;
  const shotFile = shotIdx >= 0 ? argv[shotIdx + 1] : null;
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: viewport[0], height: viewport[1] } });
  if (initFile) await page.addInitScript({ content: readFileSync(initFile, "utf8") });
  await page.goto(url, { waitUntil: "load", timeout: 30000 });
  await page.waitForTimeout(waitMs);
  if (shotFile) await page.screenshot({ path: shotFile, fullPage: true });
  const result = await runProbe(page);
  await browser.close();
  if (argv.includes("--json")) {
    console.log(JSON.stringify({ url, score: scoreOf(result.issues), ...result }, null, 2));
  } else {
    report(url, result);
  }
}

main().catch((err) => {
  console.error(String(err && err.message ? err.message : err));
  process.exit(1);
});
