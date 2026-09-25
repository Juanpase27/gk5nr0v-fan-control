#!/usr/bin/env python3
"""EC fan control driver for TongFang GK5NR0V (EVOO EG-LP7) on kernel 7.x.

Native access to the redesigned ec_sys interface: /sys/kernel/debug/ec/ec0/io
(256 bytes, file offset == EC address). Reads use os.pread (one ec_read
transaction per byte), writes use os.pwrite (one ec_write per byte). No
nbfc-linux / ec_probe dependency.

Register map (see docs/ec-register-map.md):
  0x3E (62)   CPU fan duty 0-100, firmware rewrites it every 0.2-0.6 s
  0x4C (76)   EC CPU-ish temperature (reads ~15-20 C below k10temp)
  0x60-61     CPU fan RPM, BE16
  0x68-69     GPU fan RPM, BE16 (0 = dGPU fan-stop)

Safety rules baked in:
  - writes go ONLY to 0x3E, values clamped to 0-100
  - k10temp hard guard (default 88 C) aborts any hold/sweep phase
  - stopping writes is always safe: firmware reclaims control in < 1 s

Usage (root):
  ec-fan-driver.py watch   [secs] [rate_hz]
  ec-fan-driver.py latency [trials_csv]      # e.g. 40,80,25
  ec-fan-driver.py hold    <duty> <secs>
  ec-fan-driver.py sweep   <duties_csv> <secs_each>
  ec-fan-driver.py curve   <spec> <secs>     # e.g. "45:64,55:71,65:77,75:83,88:130"
                                               duty until k10temp C; 1.5 C hysteresis
"""
import os
import signal
import subprocess
import sys
import time

EC_IO = "/sys/kernel/debug/ec/ec0/io"
OFF_DUTY = 0x3E          # 62
OFF_EC_TEMP = 0x4C       # 76
OFF_CPU_TACH = 0x60      # 96..97 BE16
OFF_GPU_TACH = 0x68      # 104..105 BE16
K10TEMP = "/sys/class/hwmon/hwmon5/temp1_input"
TEMP_GUARD_C = 88.0
HOLD_HZ = 10.0           # rewrite period: must beat the firmware loop

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTDIR = os.path.join(REPO, "data", "tests")


class EC:
    def __init__(self, path=EC_IO):
        self.fd = os.open(path, os.O_RDWR)

    def read(self, off, n):
        return os.pread(self.fd, n, off)

    def u8(self, off):
        return self.read(off, 1)[0]

    def u16be(self, off):
        b = self.read(off, 2)
        return (b[0] << 8) | b[1]

    def write_duty(self, value):
        """Only 0x3E is ever written; clamp to the valid duty range."""
        v = max(0, min(100, int(value)))
        os.pwrite(self.fd, bytes([v]), OFF_DUTY)


def k10temp_c():
    try:
        with open(K10TEMP) as f:
            return int(f.read().strip()) / 1000.0
    except (OSError, ValueError):
        return -1.0


def k10temp_smooth(n=3):
    """Median of n reads ~20 ms apart: filters single-sample Tctl spikes
    (observed 78->98 C in 200 ms on a burst) without lagging real ramps."""
    vals = []
    for _ in range(n):
        vals.append(k10temp_c())
        time.sleep(0.02)
    vals = sorted(vals)
    return vals[len(vals) // 2]


def sample(ec, phase, t0=None):
    t = time.monotonic()
    duty = ec.u8(OFF_DUTY)
    cpu = ec.u16be(OFF_CPU_TACH)
    gpu = ec.u16be(OFF_GPU_TACH)
    et = ec.u8(OFF_EC_TEMP)
    k10 = k10temp_c()
    ts = f"{(t - t0):9.3f}" if t0 is not None else f"{t:12.3f}"
    return (f"{ts},{phase},{duty},{cpu},{gpu},{et},{k10:.1f}", duty, k10)


class Guard:
    """Abort holds/sweeps if k10temp crosses TEMP_GUARD_C."""

    def __init__(self):
        self.tripped = False

    def check(self, k10):
        if 0 < k10 >= TEMP_GUARD_C:
            self.tripped = True
        return not self.tripped


def csv_open(name):
    os.makedirs(OUTDIR, exist_ok=True)
    path = os.path.join(OUTDIR, f"{name}_{time.strftime('%Y%m%d_%H%M%S')}.csv")
    f = open(path, "w", buffering=1)
    f.write("time_s,phase,duty_0x3E,cpu_rpm_0x60BE16,gpu_rpm_0x68BE16,ec_temp_0x4C,k10temp_c\n")
    return f, path


def run_phase_watch(ec, f, secs, rate):
    t_end = time.monotonic() + secs
    dt = 1.0 / rate
    t_next = time.monotonic()
    while True:
        now = time.monotonic()
        if now >= t_end:
            break
        line, _, _ = sample(ec, "watch")
        f.write(line + "\n")
        t_next += dt
        sleep = t_next - time.monotonic()
        if sleep > 0:
            time.sleep(sleep)


def cmd_watch(ec, secs, rate):
    f, path = csv_open("watch")
    print(f"logging {secs:.0f}s at {rate:.1f} Hz -> {path}")
    run_phase_watch(ec, f, secs, rate)
    f.close()
    return path


def cmd_latency(ec, trials):
    f, path = csv_open("revert_latency")
    print(f"revert-latency trials {trials} -> {path}")
    for duty in trials:
        # settle: let the firmware own the register for 2 s first
        run_phase_watch(ec, f, 2.0, 5.0)
        ec.write_duty(duty)
        t0 = time.monotonic()
        f.write(f"{0.0:9.3f},write,{duty},,,,\n")
        # poll the duty byte at ~50 Hz until the firmware disagrees
        dt = 0.02
        while True:
            elapsed = time.monotonic() - t0
            if elapsed > 5.0:
                f.write(f"{elapsed:9.3f},revert_timeout,,,,\n")
                print(f"  duty={duty}: NO revert in 5s (!)")
                break
            cur = ec.u8(OFF_DUTY)
            f.write(f"{elapsed:9.3f},poll,{cur},,,,\n")
            if cur != duty:
                print(f"  duty={duty}: firmware reverted after {elapsed*1000:.0f} ms (->{cur})")
                break
            time.sleep(dt)
    f.close()
    return path


def run_phase_hold(ec, f, guard, duty, secs, phase):
    """Rewrite duty at HOLD_HZ; sample telemetry every other cycle."""
    t0 = time.monotonic()
    dt = 1.0 / HOLD_HZ
    t_next = t0
    n = 0
    while True:
        now = time.monotonic()
        if now - t0 >= secs:
            break
        ec.write_duty(duty)
        if n % 2 == 0:
            line, cur, k10 = sample(ec, phase, t0)
            f.write(line + "\n")
            if not guard.check(k10):
                print(f"  GUARD TRIPPED: k10temp={k10:.1f}C -> releasing control")
                return False
            if cur != duty:
                print(f"  warning: duty readback {cur} != {duty} @t={now-t0:.1f}s")
        t_next += dt
        sleep = t_next - time.monotonic()
        if sleep > 0:
            time.sleep(sleep)
        n += 1
    return True


def cmd_hold(ec, duty, secs):
    f, path = csv_open("hold")
    guard = Guard()
    print(f"hold duty={duty} for {secs:.0f}s at {HOLD_HZ:.0f} Hz -> {path}")
    run_phase_watch(ec, f, 5.0, 5.0)          # baseline: firmware auto
    ok = run_phase_hold(ec, f, guard, duty, secs, "hold")
    run_phase_watch(ec, f, 15.0, 5.0)         # released: firmware reclaims
    f.close()
    print("OK" if ok else "ABORTED (guard)")
    return path, ok


def cmd_sweep(ec, duties, secs_each):
    f, path = csv_open("sweep")
    guard = Guard()
    print(f"sweep duties {duties}, {secs_each:.0f}s each -> {path}")
    run_phase_watch(ec, f, 5.0, 5.0)
    for duty in duties:
        if not run_phase_hold(ec, f, guard, duty, secs_each, f"sweep_{duty}"):
            break
        run_phase_watch(ec, f, 5.0, 5.0)      # gap: firmware auto between steps
    run_phase_watch(ec, f, 20.0, 5.0)
    f.close()
    return path


def parse_curve(spec):
    """'45:64,55:71,...' -> [(duty, temp_threshold_C), ...] ascending by temp."""
    bands = []
    for part in spec.split(","):
        duty, t = part.strip().split(":")
        bands.append((int(duty), float(t)))
    return sorted(bands, key=lambda b: b[1])


def curve_duty(bands, temp, current):
    """Pick duty for temp with 1.5 C hysteresis: dropping a band requires
    cooling 1.5 C below its threshold, so the fan does not oscillate."""
    target = bands[0][0]
    for duty, t in bands:
        if temp >= t - (1.5 if duty < current else 0.0):
            target = duty
    return target


def cmd_curve(ec, spec, secs):
    bands = parse_curve(spec)
    f, path = csv_open("curve_demo")
    guard = Guard()
    print(f"curve {bands} for {secs:.0f}s -> {path}")
    run_phase_watch(ec, f, 5.0, 5.0)
    t0 = time.monotonic()
    dt = 1.0 / HOLD_HZ
    t_next = t0
    current = bands[0][0]
    n = 0
    ok = True
    while True:
        now = time.monotonic()
        if now - t0 >= secs:
            break
        if n % 2 == 0:                        # decide at 5 Hz, write at 10 Hz
            k10 = k10temp_smooth(2)
            current = curve_duty(bands, k10, current)
            if not guard.check(k10):
                print(f"  GUARD TRIPPED: k10temp={k10:.1f}C -> releasing")
                ok = False
                break
        ec.write_duty(current)
        if n % 2 == 0:
            line, cur, _ = sample(ec, f"curve_d{current}", t0)
            f.write(line + "\n")
        t_next += dt
        sleep = t_next - time.monotonic()
        if sleep > 0:
            time.sleep(sleep)
        n += 1
    run_phase_watch(ec, f, 15.0, 5.0)
    f.close()
    print("OK" if ok else "ABORTED (guard)")
    return path, ok


def main():
    if os.geteuid() != 0:
        sys.exit("error: run as root")
    if not os.path.exists(EC_IO):
        sys.exit("error: %s missing (modprobe ec_sys write_support=1)" % EC_IO)

    # nbfc would fight us for 0x3E; park it if present
    had_nbfc = False
    try:
        r = subprocess.run(["systemctl", "is-active", "--quiet", "nbfc_service"])
        had_nbfc = r.returncode == 0
    except OSError:
        pass
    if had_nbfc:
        subprocess.run(["systemctl", "stop", "nbfc_service"], check=False)

    interrupted = {"flag": False}

    def on_sig(signum, frame):
        interrupted["flag"] = True

    signal.signal(signal.SIGINT, on_sig)

    ec = EC()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "watch"
    try:
        if cmd == "watch":
            secs = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
            rate = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
            cmd_watch(ec, secs, rate)
        elif cmd == "latency":
            trials = [int(x) for x in (sys.argv[2] if len(sys.argv) > 2 else "40,80,25").split(",")]
            cmd_latency(ec, trials)
        elif cmd == "hold":
            duty = int(sys.argv[2]) if len(sys.argv) > 2 else 60
            secs = float(sys.argv[3]) if len(sys.argv) > 3 else 45.0
            cmd_hold(ec, duty, secs)
        elif cmd == "sweep":
            duties = [int(x) for x in sys.argv[2].split(",")] if len(sys.argv) > 2 else [30, 40, 50, 60, 70, 80]
            secs = float(sys.argv[3]) if len(sys.argv) > 3 else 25.0
            cmd_sweep(ec, duties, secs)
        elif cmd == "curve":
            spec = sys.argv[2] if len(sys.argv) > 2 else "45:64,55:71,65:77,75:83,88:130"
            secs = float(sys.argv[3]) if len(sys.argv) > 3 else 240.0
            cmd_curve(ec, spec, secs)
        else:
            sys.exit(__doc__)
    finally:
        if interrupted["flag"]:
            print("\ninterrupted: writes stopped, firmware reclaims control")
        if had_nbfc:
            subprocess.run(["systemctl", "start", "nbfc_service"], check=False)


if __name__ == "__main__":
    main()
