# gk5nr0v-fans (DKMS module, read-only)

Exposes the TongFang GK5NR0V / EVOO EG-LP7 fan tachometers to the
standard Linux hwmon interface, so any monitoring app (`sensors`,
CoolerControl, fan2go, desktop widgets) can display real fan RPMs.

```
$ sensors | grep -A3 gk5nr0v
gk5nr0v_fans-isa-0000
Adapter: ISA adapter
CPU fan:      572 RPM
GPU fan:        0 RPM
```

- Reads EC 0x60-0x61 (CPU tach BE16) and 0x68-0x69 (GPU tach BE16)
  via the kernel's own `ec_read()` — transactions are serialized by the
  ACPI EC mutex, so it coexists with nbfc-linux writing duty 0x3E.
- **Strictly read-only**: no EC writes, no pwm channels. Control stays
  with nbfc-linux + the v2 curve config (that separation is deliberate:
  see `docs/kernel7-session-20260925.md` for why a control-side module
  is a much bigger project).
- Register map: `docs/ec-register-map.md`.

## Install (CachyOS / any Arch with a Clang-built kernel)

```bash
sudo mkdir -p /usr/src/gk5nr0v-fans-1.0.0
sudo cp gk5nr0v-fans.c Makefile dkms.conf /usr/src/gk5nr0v-fans-1.0.0/
sudo dkms add -m gk5nr0v-fans -v 1.0.0
sudo dkms build -m gk5nr0v-fans -v 1.0.0
sudo dkms install -m gk5nr0v-fans -v 1.0.0
echo gk5nr0v-fans | sudo tee /etc/modules-load.d/gk5nr0v-fans.conf
sudo modprobe gk5nr0v-fans
sensors | grep -A3 gk5nr0v
```

CachyOS kernels are Clang/LLD/ThinLTO builds: the module must be built
with `CC=clang LD=ld.lld` (already baked into `dkms.conf` and the
Makefile workflow here). DKMS rebuilds it automatically on every kernel
update. Not upstreamable (laptop-specific reverse-engineered registers);
it lives out-of-tree like tuxedo-drivers does.
