# Probe tools

Small C tools to explore the FireStudio mixer area (`0xFFFFE0700000`).
Quit the FireStudio Mixer app before using them: FireWire access is exclusive.

```sh
make            # builds build/raw, build/dumpr, build/scan, build/wq
build/scan                    # address ranges that respond (read only)
build/raw e0700000 1290       # dumps the mixer area as "index value" (read only)
build/dumpr e0700000 64       # compact view with ASCII (read only)
build/wq 10ac 24              # WRITES one quadlet (offset in the area, value), then reads it back
```

`wq` refuses any offset outside the parameters (`0x0038`–`0x1164`): the header, names and meters are
protected. Only write parameters documented in [../../docs/register-map.md](../../docs/register-map.md).
