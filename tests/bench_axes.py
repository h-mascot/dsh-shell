#!/usr/bin/env python3
"""MAC-DESIGN-BENCH-2026 axes 1-5 receipt runner for DSH Shell v3.

Collects live AX evidence from the running app and writes bench-axis*.json
receipts. Each axis PASS requires every assertion cited below to hold.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

OUT = Path("/Users/enterprise/.hermes/output/dsh-shell-v3")
PID = int(subprocess.check_output(["pgrep", "-x", "dsh-shell"]).split()[0])
APP = Path("/Users/enterprise/Code/dsh-shell/.build/DSH Shell.app")

receipt = {"pid": PID, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "assertions": {}, "pass": False}


def axdump(depth: int) -> str:
    return subprocess.run(["/tmp/axdump", str(PID), str(depth)], capture_output=True, text=True, timeout=60).stdout


def axfind(term: str) -> str:
    return subprocess.run(["/tmp/axfind", str(PID), term], capture_output=True, text=True, timeout=60).stdout


def axmenuwalk() -> str:
    return subprocess.run(["/tmp/axmenuwalk", str(PID)], capture_output=True, text=True, timeout=60).stdout


def press_exact(title: str) -> bool:
    r = subprocess.run(["/tmp/axpress_appmenu", str(PID), title], capture_output=True, text=True, timeout=60)
    return r.returncode == 0


def windows() -> list:
    r = subprocess.run(["/tmp/axallwins", str(PID)], capture_output=True, text=True, timeout=60).stdout
    return [l for l in r.splitlines() if "AXStandardWindow" in l or "count" in l]


def capture(name: str) -> str:
    path = OUT / name
    wid = subprocess.check_output(["/tmp/winid"], text=True).strip()
    subprocess.run(["screencapture", "-x", f"-l{wid}", str(path)], check=True, timeout=30)
    return str(path)


def gate_receipt() -> str:
    log = OUT / "gate-log.txt"
    r = subprocess.run(
        ["/bin/zsh", "-c", "cd /Users/enterprise/Code/dsh-shell && ./scripts/ctrl-gate.sh"],
        capture_output=True, text=True, timeout=600,
    )
    log.write_text(r.stdout + "\n-- stderr --\n" + r.stderr)
    ok = "CTRL gate passed" in r.stdout
    return f"gate={'PASS' if ok else 'FAIL'} log={log}"


# ---------- Axis 1: platform conventions ----------
a1 = {}
menus = axmenuwalk()
for needed in ["About DSH Shell", "Settings…", "Hide DSH Shell", "Quit DSH Shell",
               "New Tab", "Open Location…", "Close Tab",
               "Minimize", "Zoom", "Rename Tab…",
               "Show Next Tab", "Show Previous Tab", "Select Tab 1"]:
    a1[f"menu:{needed}"] = needed in menus
a1["edit:copy/paste present"] = "Copy" in menus and "Paste" in menus
a1["gate"] = "PASS" in gate_receipt()
receipt["assertions"]["axis1"] = a1
receipt["axis1_pass"] = all(a1.values())

json.dump(receipt, open(OUT / "bench-axis1.json", "w"), indent=2)
print("AXIS1", "PASS" if receipt["axis1_pass"] else "FAIL", json.dumps(a1))
