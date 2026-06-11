#!/usr/bin/env python3
"""Live tuner for blackhole.glsl — run it inside Ghostty.

Parses the `const float NAME = VALUE;` block at the top of the shader,
lets you nudge values with the keyboard, rewrites the file and triggers
a Ghostty config reload (cmd+shift+,) so the shader hot-reloads.

Keys:
  up/down or k/j   select parameter
  left/right h/l   nudge value by step
  shift + h/l      nudge by 10x step
  s                type an exact value
  r                force a reload
  q / ctrl-c       quit
"""

import math
import os
import re
import select
import signal
import subprocess
import sys
import tempfile
import termios
import tty

SHADER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "blackhole.glsl")
FLOAT_RE = r"[+-]?(?:(?:\d+\.\d*)|(?:\.\d+)|(?:\d+))(?:[eE][+-]?\d+)?"
CONST_RE = re.compile(
    rf"^(const float\s+)(\w+)(\s*=\s*)({FLOAT_RE})(\s*;.*)$"
)
BOUNDS = {
    "HOLE_RADIUS": (0.001, 0.5),
    "LENS_STRENGTH": (0.0, 2.0),
    "DISK_GAIN": (0.0, 10.0),
    "DRIFT_SPEED": (0.0, 10.0),
    "DISK_TILT": (-6.2832, 6.2832),
    "WORK_AREA": (0.0, 0.9),
    "DILATION_MIN": (0.0, 1.0),
    "WORK_PERIOD_MIN": (1.0 / 60.0, 24.0 * 60.0),
    "BREAK_MIN": (0.0, 24.0 * 60.0),
    "IDLE_FADE_SEC": (0.0, 24.0 * 60.0 * 60.0),
    "REST_INTENSITY_MIN": (0.0, 1.0),
    "REST_VIS_MIN": (0.0, 1.0),
    "TIME_SCALE": (0.001, 10000.0),
}


def read_shader():
    with open(SHADER, encoding="utf-8", newline="") as f:
        return f.readlines()


def scan_params(lines):
    params = []
    seen = set()
    duplicates = set()
    for i, line in enumerate(lines):
        m = CONST_RE.match(line)
        if not m:
            continue
        name = m.group(2)
        if name in seen:
            duplicates.add(name)
            continue
        seen.add(name)
        params.append([name, float(m.group(4))])
    if duplicates:
        raise ValueError(f"duplicate const float: {', '.join(sorted(duplicates))}")
    return params


def load():
    lines = read_shader()
    return scan_params(lines)


def validate_param(name, value):
    if not math.isfinite(value):
        return False, f"{name} must be finite"
    if name in BOUNDS:
        lo, hi = BOUNDS[name]
        if value < lo or value > hi:
            return False, f"{name} must be between {lo:g} and {hi:g}"
    return True, ""


def write_shader(lines):
    shader_dir = os.path.dirname(SHADER)
    tmp_name = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            dir=shader_dir,
            delete=False,
            encoding="utf-8",
            newline="",
        ) as f:
            tmp_name = f.name
            f.writelines(lines)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_name, SHADER)
        tmp_name = None
    finally:
        if tmp_name is not None:
            try:
                os.unlink(tmp_name)
            except FileNotFoundError:
                pass


def save_value(name, value, params):
    ok, err = validate_param(name, value)
    if not ok:
        raise ValueError(err)

    lines = read_shader()
    scan_params(lines)
    matches = []
    for i, line in enumerate(lines):
        m = CONST_RE.match(line)
        if m and m.group(2) == name:
            matches.append((i, m))

    if not matches:
        raise ValueError(f"{name} is missing or no longer a simple const float")
    if len(matches) > 1:
        raise ValueError(f"{name} is duplicated")

    i, m = matches[0]
    lines[i] = f"{m.group(1)}{m.group(2)}{m.group(3)}{value:.4f}{m.group(5)}\n"
    write_shader(lines)


def reload_ghostty():
    # Ghostty (>= 1.2) reloads its config — including custom shaders — on
    # SIGUSR2. No focus or Accessibility permission needed. PIDs come from ps,
    # not pgrep/pkill: those silently exclude their own ancestors, and Ghostty
    # is an ancestor of the shell this tuner runs in.
    out = subprocess.run(["ps", "-axco", "pid,comm"],
                         capture_output=True, text=True).stdout
    ok = False
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[1].strip() == "ghostty":
            try:
                os.kill(int(parts[0]), signal.SIGUSR2)
                ok = True
            except OSError:
                pass
    return ok, "" if ok else "is Ghostty running?"


def step_for(value):
    if value == 0.0:
        return 0.01
    return 10.0 ** (math.floor(math.log10(abs(value))) - 1)


def read_key():
    ch = sys.stdin.read(1)
    if ch != "\x1b":
        return ch

    if not select.select([sys.stdin], [], [], 0.1)[0]:
        return ""
    if sys.stdin.read(1) != "[":
        return ""
    if not select.select([sys.stdin], [], [], 0.1)[0]:
        return ""
    return {"A": "up", "B": "down", "C": "right", "D": "left"}.get(sys.stdin.read(1), "")


def draw(params, sel, status):
    sys.stdout.write("\x1b[2J\x1b[H")
    print("black hole tuner — j/k select, h/l nudge, H/L coarse, s set, r reload, q quit\n")
    for i, (name, value) in enumerate(params):
        cursor = "\x1b[7m" if i == sel else ""
        print(f"  {cursor}{name:<19} {value:>10.4f}\x1b[0m   step {step_for(value):g}")
    print(f"\n  {status}")
    sys.stdout.flush()


def prompt_value(fd, old_settings):
    termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    try:
        raw = input("\n  new value: ")
        value = float(raw)
        if not math.isfinite(value):
            return None, "value must be finite"
        return value, ""
    except ValueError:
        return None, "value must be a number"
    finally:
        tty.setcbreak(fd)


def refresh_params(params, sel):
    selected = params[sel][0] if params else None
    params = load()
    if selected:
        for i, (name, _) in enumerate(params):
            if name == selected:
                return params, i
    return params, min(sel, max(0, len(params) - 1))


def main():
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        sys.exit("tune.py must be run in an interactive terminal")

    try:
        params = load()
    except (OSError, UnicodeDecodeError, ValueError) as e:
        sys.exit(f"failed to load {SHADER}: {e}")
    if not params:
        sys.exit(f"no `const float` params found in {SHADER}")
    sel, status = 0, f"{len(params)} params from {os.path.basename(SHADER)}"

    fd = sys.stdin.fileno()
    old_settings = None
    cbreak_enabled = False
    try:
        old_settings = termios.tcgetattr(fd)
        tty.setcbreak(fd)
        cbreak_enabled = True
        while True:
            draw(params, sel, status)
            key = read_key()
            changed_name = None
            changed_value = None
            if key in ("q", "\x03"):
                break
            elif key in ("k", "up"):
                sel = (sel - 1) % len(params)
            elif key in ("j", "down"):
                sel = (sel + 1) % len(params)
            elif key in ("h", "l", "H", "L", "left", "right"):
                name, value = params[sel]
                direction = 1 if key in ("l", "L", "right") else -1
                coarse = 10.0 if key in ("H", "L") else 1.0
                candidate = round(value + direction * coarse * step_for(value), 6)
                ok, err = validate_param(name, candidate)
                if ok:
                    params[sel][1] = candidate
                    changed_name, changed_value = name, candidate
                else:
                    status = err
            elif key == "s":
                name = params[sel][0]
                v, err = prompt_value(fd, old_settings)
                if v is None:
                    status = err
                else:
                    ok, err = validate_param(name, v)
                    if ok:
                        params[sel][1] = v
                        changed_name, changed_value = name, v
                    else:
                        status = err
            elif key == "r":
                ok, err = reload_ghostty()
                status = "reloaded" if ok else f"reload failed ({err or 'grant Accessibility to Ghostty'})"

            if changed_name is not None:
                try:
                    save_value(changed_name, changed_value, params)
                    params, sel = refresh_params(params, sel)
                except (OSError, UnicodeDecodeError, ValueError) as e:
                    status = f"save failed: {e}"
                    continue
                ok, err = reload_ghostty()
                status = (
                    f"saved {changed_name} = {changed_value:.4f}, reloaded"
                    if ok else
                    f"saved, but reload failed ({err or 'grant Accessibility to Ghostty'}) "
                    f"— press cmd+shift+, manually"
                )
    finally:
        if cbreak_enabled and old_settings is not None:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        print()


if __name__ == "__main__":
    main()
