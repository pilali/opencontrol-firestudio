# Probe tools

Small C tools to explore the FireStudio mixer area (`0xFFFFE0700000`).
They open the unit exclusively, which briefly restarts the audio stream: use them while nothing is playing.

```sh
make            # builds build/raw, build/dumpr, build/scan, build/wq, build/opmode, build/units
build/scan                    # address ranges that respond (read only)
build/raw e0700000 1290       # dumps the mixer area as "index value" (read only)
build/dumpr e0700000 64       # compact view with ASCII (read only)
build/wq 10ac 24              # WRITES one quadlet (offset in the area, value), then reads it back
```

`opmode` talks to the PreSonus driver, not to the interface, and can run while the app is open:

```sh
build/opmode                  # prints the driver operation mode (0-3)
build/opmode 2                # sets it (restarts the audio stream), see ../../docs/driver-settings.md
build/units                   # units seen on the FireWire bus and by the driver (read only)
```

`wq` refuses any offset outside the parameters (`0x0038`–`0x1164`): the header, names and meters are
protected. Only write parameters documented in [../../docs/register-map.md](../../docs/register-map.md).

The mixer tools (`raw`, `dumpr`, `scan`, `wq`) open the first FireStudio found.
