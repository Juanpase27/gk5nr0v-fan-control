#!/usr/bin/env python3
"""Stress validation for the gk5nr0v-fan-control stack.

Runs timed load phases while logging, once per second, BOTH access paths
(direct EC via ec_sys io, and the gk5nr0v-fans hwmon module) plus k10temp
and dGPU core temp. Cross-source agreement and fan response to each phase
are the pass criteria:

  idle       - both fans at rest floors (CPU at v2 curve floor, GPU fan-stop)
  cpu_load   - k10temp rises, duty follows v2 bands, CPU RPM staircase up
  gpu_load   - dGPU core rises, GPU fan stays 0 until ~55 C then spins up
  recovery   - temps fall, fans return to floors, GPU back to fan-stop

Usage (root): stress-validation.py [csv_path]
"""
import glob
import os
import subprocess
import sys
import threading
import time

EC_IO = "/sys/kernel/debug/ec/ec0/io"
OFF_DUTY = 0x3E

PHASES = [
    ("idle", 30),
    ("cpu_load", 120),
    ("gpu_load", 120),
    ("recovery", 60),
]
WIDGET_IPC = ["quickshell", "-p",
              "/home/juan/.config/quickshell/caelestia/shell.qml",
              "ipc", "call", "fans", "readings"]
WIDGET_ENV = dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000")


def hwmon_by_name(name):
    for f in glob.glob("/sys/class/hwmon/hwmon*/name"):
        try:
            with open(f) as fh:
                if fh.read().strip() == name:
                    return os.path.dirname(f)
        except OSError:
            continue
    return None


def read_int(path):
    try:
        with open(path) as fh:
            return int(fh.read().strip())
    except (OSError, ValueError):
        return -1


class Logger(threading.Thread):
    def __init__(self, csv_path):
        super().__init__(daemon=True)
        self.csv_path = csv_path
        self.phase = "startup"
        self.running = True
        self.gpu_t = -1.0
        self.f = open(csv_path, "w", buffering=1)
        self.f.write("time_s,phase,duty_ec,cpu_rpm_ec,gpu_rpm_ec,"
                     "cpu_rpm_hwmon,gpu_rpm_hwmon,k10temp_c,gpu_core_c\n")

    def run(self):
        ec = os.open(EC_IO, os.O_RDONLY)
        fans = hwmon_by_name("gk5nr0v_fans")
        k10 = hwmon_by_name("k10temp")
        t0 = time.monotonic()
        tick = 0
        while self.running:
            duty = os.pread(ec, 1, OFF_DUTY)[0]
            cpu_ec = int.from_bytes(os.pread(ec, 2, 0x60), "big")
            gpu_ec = int.from_bytes(os.pread(ec, 2, 0x68), "big")
            cpu_hm = read_int(f"{fans}/fan1_input") if fans else -1
            gpu_hm = read_int(f"{fans}/fan2_input") if fans else -1
            k10v = read_int(f"{k10}/temp1_input") / 1000.0 if k10 else -1
            if tick % 2 == 0:
                try:
                    out = subprocess.run(
                        ["nvidia-smi", "--query-gpu=temperature.gpu",
                         "--format=csv,noheader"],
                        capture_output=True, text=True, timeout=5)
                    if out.returncode == 0:
                        self.gpu_t = float(out.stdout.strip().splitlines()[0])
                except (OSError, ValueError, subprocess.TimeoutExpired):
                    pass
            self.f.write(f"{time.monotonic()-t0:7.1f},{self.phase},"
                         f"{duty},{cpu_ec},{gpu_ec},{cpu_hm},{gpu_hm},"
                         f"{k10v:.1f},{self.gpu_t:.0f}\n")
            tick += 1
            time.sleep(1.0)


def widget_sample():
    try:
        out = subprocess.run(WIDGET_IPC, capture_output=True, text=True,
                             timeout=10, env=WIDGET_ENV)
        return out.stdout.strip() if out.returncode == 0 else "ipc-error"
    except (OSError, subprocess.TimeoutExpired):
        return "ipc-error"


def spawn_cpu_load(secs):
    procs = []
    for _ in range(16):
        procs.append(subprocess.Popen(
            ["timeout", str(secs), "yes"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    return procs


def spawn_gpu_load(secs):
    procs = []
    for _ in range(2):
        procs.append(subprocess.Popen(
            ["timeout", str(secs), "ffmpeg", "-hide_banner", "-loglevel",
             "error", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=60",
             "-vf", "hwupload_cuda,scale_cuda", "-c:v", "h264_nvenc",
             "-b:v", "20M", "-f", "null", "-"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    return procs


def main():
    if os.geteuid() != 0:
        sys.exit("error: run as root")
    csv_path = sys.argv[1] if len(sys.argv) > 1 else \
        "/tmp/stress_validation.csv"
    logger = Logger(csv_path)
    logger.start()
    time.sleep(1)
    procs = []
    try:
        for phase, secs in PHASES:
            logger.phase = phase
            print(f"== phase {phase} ({secs}s) ==", flush=True)
            if phase == "cpu_load":
                procs = spawn_cpu_load(secs)
            elif phase == "gpu_load":
                procs = spawn_gpu_load(secs)
            elif phase == "recovery":
                for p in procs:
                    p.terminate()
                procs = []
            time.sleep(secs)
            print(f"   widget @end-{phase}: {widget_sample()}", flush=True)
    finally:
        for p in procs:
            p.terminate()
        time.sleep(1)
        logger.running = False
        logger.join(timeout=3)
        logger.f.close()
        print(f"csv: {csv_path}", flush=True)


if __name__ == "__main__":
    main()
