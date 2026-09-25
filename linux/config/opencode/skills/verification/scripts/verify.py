#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence

HERE = Path(__file__).resolve().parent
REGISTRY_PATH = HERE / "registry.json"
VERIFIERS_DIR = HERE.parent / "verifiers"
DEFAULT_TIMEOUT = int(os.environ.get("VERIFY_TIMEOUT", "120"))

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_ERROR = 2

STATUS_OK = "OK"
STATUS_FAIL = "FAIL"
STATUS_SKIP = "SKIP"


@dataclass(frozen=True)
class Domain:
    name: str
    script: str
    desc: str
    globs: tuple[str, ...]
    priority: int


@dataclass
class Check:
    status: str
    name: str
    detail: str


def load_domains() -> dict[str, Domain]:
    raw = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    domains: dict[str, Domain] = {}
    for name, spec in raw.get("domains", {}).items():
        domains[name] = Domain(
            name=name,
            script=str(spec["script"]),
            desc=str(spec.get("desc", "")),
            globs=tuple(str(g) for g in spec.get("globs", ())),
            priority=int(spec.get("priority", 0)),
        )
    return domains


def expand(pattern: str) -> str:
    return str(Path(pattern).expanduser())


def matches(path: str, domain: Domain) -> bool:
    candidates = {path, expand(path)}
    try:
        candidates.add(str(Path(path).expanduser().resolve()))
    except OSError:
        pass
    for glob in domain.globs:
        target = expand(glob)
        if any(fnmatch.fnmatch(c, target) for c in candidates):
            return True
    return False


def detect(domains: dict[str, Domain], paths: Sequence[str]) -> dict[str, set[str]]:
    chosen: dict[str, set[str]] = {}
    for path in paths:
        best: Domain | None = None
        for domain in domains.values():
            if matches(path, domain) and (best is None or domain.priority > best.priority):
                best = domain
        if best is not None:
            chosen.setdefault(best.name, set()).add(path)
    return chosen


def parse_checks(stdout: str) -> list[Check]:
    checks: list[Check] = []
    for line in stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t", 2)
        if len(parts) == 3 and parts[0] in {STATUS_OK, STATUS_FAIL, STATUS_SKIP}:
            checks.append(Check(status=parts[0], name=parts[1], detail=parts[2]))
    return checks


def run_verifier(domain: Domain, targets: Sequence[str], activate: bool) -> tuple[int, list[Check], str]:
    script = VERIFIERS_DIR / domain.script
    if not script.exists():
        return EXIT_ERROR, [], f"verificador ausente: {script}"
    env = dict(os.environ)
    if activate:
        env["VERIFY_ACTIVATE"] = "1"
    try:
        proc = subprocess.run(
            [str(script), *targets],
            capture_output=True,
            text=True,
            timeout=DEFAULT_TIMEOUT,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return EXIT_ERROR, [], f"timeout tras {DEFAULT_TIMEOUT}s"
    checks = parse_checks(proc.stdout)
    code = proc.returncode if proc.returncode in {EXIT_OK, EXIT_FAIL, EXIT_ERROR} else EXIT_ERROR
    if any(c.status == STATUS_FAIL for c in checks):
        code = max(code, EXIT_FAIL)
    hint = (proc.stderr or "").strip()
    return code, checks, hint


def render(domain_name: str, code: int, checks: list[Check], hint: str, as_json: bool, quiet: bool) -> None:
    if as_json:
        return
    if quiet:
        for check in checks:
            if check.status == STATUS_FAIL:
                print(f"[FAIL] {domain_name}/{check.name} - {check.detail}")
        if code == EXIT_ERROR and hint:
            print(f"[ERROR] {domain_name} - {hint}")
        return
    for check in checks:
        print(f"[{check.status}] {domain_name}/{check.name} - {check.detail}")
    if code == EXIT_ERROR and hint:
        print(f"[ERROR] {domain_name} - {hint}")


def cmd_list(domains: dict[str, Domain], as_json: bool) -> int:
    if as_json:
        print(json.dumps({"domains": [asdict(d) for d in domains.values()]}, ensure_ascii=False))
        return EXIT_OK
    for domain in domains.values():
        print(f"{domain.name:<12} p{domain.priority:<3} {domain.script:<14} {domain.desc}")
    return EXIT_OK


def cmd_detect(domains: dict[str, Domain], paths: Sequence[str], as_json: bool) -> int:
    chosen = detect(domains, paths)
    if as_json:
        print(json.dumps({name: sorted(files) for name, files in chosen.items()}, ensure_ascii=False))
        return EXIT_OK
    for name, files in sorted(chosen.items()):
        print(f"{name}: {' '.join(sorted(files))}")
    if not chosen:
        print("sin dominio reconocido")
    return EXIT_OK


def cmd_run(domains: dict[str, Domain], name: str, paths: Sequence[str], args: argparse.Namespace) -> int:
    domain = domains.get(name)
    if domain is None:
        if not args.json:
            print(f"dominio desconocido: {name}")
        return EXIT_ERROR
    code, checks, hint = run_verifier(domain, paths, args.activate)
    if args.json:
        print(json.dumps(
            {
                "domain": name,
                "ok": code == EXIT_OK,
                "exit": code,
                "checks": [asdict(c) for c in checks],
                "hint": hint,
            },
            ensure_ascii=False,
        ))
    else:
        render(name, code, checks, hint, args.json, args.quiet)
        if not args.quiet:
            print(f"verify: {'PASS' if code == EXIT_OK else 'FAIL'} {name}")
    return code


def cmd_auto(domains: dict[str, Domain], paths: Sequence[str], args: argparse.Namespace) -> int:
    chosen = detect(domains, paths)
    if not chosen:
        if not args.json and not args.quiet:
            print("verify: sin dominio reconocido")
        return EXIT_OK
    overall = EXIT_OK
    results: list[tuple[str, int, list[Check], str]] = []
    for name in sorted(chosen):
        code, checks, hint = run_verifier(domains[name], sorted(chosen[name]), args.activate)
        results.append((name, code, checks, hint))
        overall = max(overall, code)
    if args.json:
        print(json.dumps(
            {
                "command": "auto",
                "ok": overall == EXIT_OK,
                "exit": overall,
                "results": [
                    {"domain": n, "exit": c, "checks": [asdict(ch) for ch in checks], "hint": h}
                    for n, c, checks, h in results
                ],
            },
            ensure_ascii=False,
        ))
        return overall
    for name, code, checks, hint in results:
        render(name, code, checks, hint, args.json, args.quiet)
    if not args.quiet:
        print(f"verify: {'PASS' if overall == EXIT_OK else 'FAIL'} ({len(results)} dominio/s)")
    return overall


def cmd_selftest(domains: dict[str, Domain], as_json: bool) -> int:
    rows: list[tuple[str, str, str]] = []
    worst = EXIT_OK
    for name, domain in domains.items():
        script = VERIFIERS_DIR / domain.script
        if not script.exists():
            rows.append((name, "MISSING", str(script)))
            worst = EXIT_FAIL
            continue
        if not os.access(script, os.X_OK):
            rows.append((name, "NO-EXEC", str(script)))
            worst = EXIT_FAIL
            continue
        try:
            proc = subprocess.run([str(script), "--probe"], capture_output=True, text=True, timeout=15)
        except subprocess.TimeoutExpired:
            rows.append((name, "TIMEOUT", "--probe"))
            worst = EXIT_FAIL
            continue
        lines = [l for l in (proc.stdout or "").splitlines() if l.strip()]
        head = lines[0].split("\t") if lines else []
        if proc.returncode == EXIT_OK and head and head[0] == STATUS_OK:
            rows.append((name, "OK", "probe"))
        else:
            rows.append((name, "BAD", f"rc={proc.returncode} out={(proc.stdout or '').strip()[:80]}"))
            worst = EXIT_FAIL
    if as_json:
        print(json.dumps(
            {"command": "selftest", "ok": worst == EXIT_OK,
             "results": [{"domain": n, "status": s, "detail": d} for n, s, d in rows]},
            ensure_ascii=False,
        ))
        return worst
    for name, status, detail in rows:
        print(f"[{status}] {name} - {detail}")
    print(f"verify: {'PASS' if worst == EXIT_OK else 'FAIL'} selftest")
    return worst


def cmd_scaffold(domain: str, globs: Sequence[str], as_json: bool) -> int:
    destination = VERIFIERS_DIR / f"{domain}.sh"
    if destination.exists():
        if not as_json:
            print(f"ya existe: {destination}")
        return EXIT_FAIL
    template = (VERIFIERS_DIR / "TEMPLATE.sh").read_text(encoding="utf-8")
    destination.write_text(template.replace("DOMAIN_NAME", domain), encoding="utf-8")
    destination.chmod(0o755)
    raw = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    raw.setdefault("domains", {})[domain] = {
        "script": destination.name,
        "desc": f"verificador {domain}",
        "priority": 5,
        "globs": list(globs) or [f"~/.config/{domain}/*"],
    }
    REGISTRY_PATH.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if as_json:
        print(json.dumps({"scaffolded": domain, "script": str(destination)}, ensure_ascii=False))
    else:
        print(f"creado {destination}")
        print("editar los checks y, si aplica, afinar 'globs'/'priority' en registry.json")
    return EXIT_OK


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="verify", description="Verificacion determinista por dominio")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--activate", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    detect_parser = sub.add_parser("detect")
    detect_parser.add_argument("paths", nargs="+")
    run_parser = sub.add_parser("run")
    run_parser.add_argument("domain")
    run_parser.add_argument("paths", nargs="*")
    auto_parser = sub.add_parser("auto")
    auto_parser.add_argument("paths", nargs="+")
    scaffold_parser = sub.add_parser("scaffold")
    scaffold_parser.add_argument("domain")
    scaffold_parser.add_argument("globs", nargs="*")
    sub.add_parser("selftest")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    domains = load_domains()
    if args.command == "list":
        return cmd_list(domains, args.json)
    if args.command == "detect":
        return cmd_detect(domains, args.paths, args.json)
    if args.command == "run":
        return cmd_run(domains, args.domain, args.paths, args)
    if args.command == "auto":
        return cmd_auto(domains, args.paths, args)
    if args.command == "scaffold":
        return cmd_scaffold(args.domain, args.globs, args.json)
    if args.command == "selftest":
        return cmd_selftest(domains, args.json)
    return EXIT_ERROR


if __name__ == "__main__":
    sys.exit(main())
