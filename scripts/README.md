# Sonic VANE - Automated Build & Release System

This repository is configured with automated multi-platform building and release publishing using **Godot 4.7.2** and GitHub Actions.

---

## ⚡ How Releases Work

You **do not need to make version tags**.

Simply push to `origin main`:
```bash
git add .
git commit -m "Your commit messages"
git push origin main
```

Whenever you push to `origin main`:
1. **Date-based Release:** The release is automatically created and tagged with the date of the push (e.g. `2026-10-09`). If multiple pushes occur on the same day, it increments automatically (e.g. `2026-10-09.2`, `2026-10-09.3`).
2. **Multi-Commit Changelog:** If a push contains multiple commits, all commits included in that specific push to origin are automatically extracted and listed in the release changelog with direct links and author names.
3. **Automated Multi-Platform Build:** Godot builds Windows, Linux, and macOS packages along with all modular PCKs.

---

## 📦 Export Structure

The game uses a modular PCK architecture loaded at runtime by `ContentPackManager.gd`:

- **Preset 0 ("Windows Desktop")** $\rightarrow$ `SonicVANE_WIN.exe`
- **Preset 1 ("Linux")** $\rightarrow$ `SonicVANE_LINUX.x86_64`
- **Preset 2 ("macOS")** $\rightarrow$ `SonicVANE_MAC.app`
- **Presets 3..N (Data & Levels)**:
  - Base packs $\rightarrow$ `Data/<name>.pck` (`audio.pck`, `characters.pck`, `objects.pck`, `shared.pck`)
  - Level packs $\rightarrow$ `Data/Levels/<name>.pck` (`cityescape.pck`, `emeraldcoast.pck`, etc.)
  - Mods $\rightarrow$ `Data/Mods/` directory

### Packaged Zip Archives

Three release packages are generated in `dist/` and attached to the release:

| Package | Contents |
| :--- | :--- |
| **`SonicVANE-Windows.zip`** | `SonicVANE_WIN.exe` + `Data/` (containing all base PCKs & `Levels/*.pck`) |
| **`SonicVANE-Linux.zip`** | `SonicVANE_LINUX.x86_64` (executable) + `Data/` |
| **`SonicVANE-macOS.zip`** | `SonicVANE_MAC.app` + `Data/` |

---

## 💻 Running the Build Locally

You can test the build script locally at any time:

```bash
# Preview what would be built without running Godot
python scripts/build_game.py --dry-run

# Run full export (point to your local Godot executable)
python scripts/build_game.py --godot "C:\path\to\Godot.exe"
```
