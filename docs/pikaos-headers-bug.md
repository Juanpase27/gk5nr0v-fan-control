# PikaOS 4 broken kernel headers — acpi-call-dkms cannot build

## Symptom

`acpi-call-dkms` (a dependency of nbfc-linux) fails to build for kernel
`7.2.4-pikaos` while building fine for `7.1.8-pikaos`:

```
/usr/src/linux-headers-7.2.4-pikaos/include/linux/kconfig.h:5:10:
fatal error: 'generated/autoconf.h' file not found
```

## Root cause

The `linux-headers-7.2.4-pikaos` package (`7.2.4-101pika1`) ships an
incomplete header tree:

- `include/generated/autoconf.h` is missing (present in the 7.1.8 package).
- `scripts/kconfig/` sources are missing too, so
  `make -C /lib/modules/7.2.4-pikaos/build modules_prepare` cannot regenerate
  it (fails at `syncconfig` with "scripts/kconfig/Makefile: No such file").

This is a PikaOS packaging bug, not an acpi-call issue.

## Workaround (used in this project)

nbfc-linux accesses the EC through `ec_sys`, so the `acpi-call` module is not
needed. Satisfy the dependency with an equivs stub:

```bash
sudo apt purge -y acpi-call-dkms        # note: this also removes an unconfigured nbfc-linux
sudo apt install -y equivs
cd config/
equivs-build acpi-call-dummy
sudo apt install -y ./acpi-call-dummy_1.0_all.deb
sudo apt install -y /path/to/nbfc-linux_0.5.3_amd64.deb   # reinstall, now configures
```

The stub control file lives at `config/acpi-call-dummy`.

## TODO

- [ ] Report upstream to PikaOS (ppa.pika-os.com / pika-os GitHub) with the
      `modules_prepare` and `make.log` evidence.
