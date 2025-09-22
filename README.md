# HyprIngMyBorder ;)

A lightweight tool written in [Zig](https://ziglang.org) for **customizing and animating window borders in [Hyprland](https://hyprland.org/)**.  
It communicates directly with Hyprland’s IPC socket for **fast, efficient, and low-overhead** border updates — no shell loops, no CPU-burning scripts.

---

## ✨ Features
- Smooth **rainbow animated borders** (HSV color cycling).
- Lightweight: written in Zig, connects directly to Hyprland IPC.
- Configurable update speed & hue step.
- Safe to run in the background — minimal CPU usage.
- Future roadmap:
  - GUI for live customization.
  - Profiles for different border styles.
  - More Hyprland integration (shadows, inactive borders, event-driven changes).

---

## 🚀 Installation

### Build from source
Make sure you have **Zig nightly (0.16+)** installed:

```bash
git clone https://github.com/blue-codes-yep/HyprIngMyBorder.git
cd HyprIngMyBorder
zig build -Doptimize=ReleaseFast
```

The compiled binary will be in:
```
zig-out/bin/hypringmyborder
```

### Run manually
```bash
./zig-out/bin/hypringmyborder &
```

### Autostart with Hyprland
Add this to your `hyprland.conf`:
```ini
exec = ~/.local/bin/hypringmyborder
```

---

## ⚙️ Configuration
For now, speed and FPS are hardcoded in `src/main.zig`:

```zig
const step: f64 = 0.01;       // hue step speed
const interval_ms: u64 = 100; // update interval (~10 fps)
```

In future releases, these will be configurable via:
- CLI flags (e.g. `--fps 30 --speed 0.01`)
- GUI frontend

---

## 🛠 Development

```bash
zig build run
```

You’ll need:
- Zig 0.16.0-dev or later
- Hyprland running (with `$XDG_RUNTIME_DIR` and `$HYPRLAND_INSTANCE_SIGNATURE` set)

---

## 📜 License
MIT — free to use, modify, and share.

---

## 💡 Inspiration
Originally started as a shell script with `hyprctl` calls.  
Re-implemented in Zig for efficiency, performance, and future extensibility.
