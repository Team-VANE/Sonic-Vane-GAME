#!/usr/bin/env python3
"""
Sonic VANE - Godot Multi-Platform Build & Packaging Script

Builds:
- Preset 0: Windows Desktop -> SonicVANE_WIN.exe
- Preset 1: Linux -> SonicVANE_LINUX.x86_64
- Preset 2: macOS -> SonicVANE_MAC.app
- Presets 3+: Base PCK packages (Data/*.pck) and Level PCK packages (Data/Levels/*.pck)

Packages into 3 release archives in dist/:
- SonicVANE-Windows.zip (contains SonicVANE_WIN.exe + Data/)
- SonicVANE-Linux.zip   (contains SonicVANE_LINUX.x86_64 + Data/)
- SonicVANE-macOS.zip   (contains SonicVANE_MAC.app + Data/)
"""

import argparse
import os
import re
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path


def parse_export_presets(presets_file: Path):
    """
    Parses export_presets.cfg and returns a list of dictionaries with preset info.
    """
    if not presets_file.is_file():
        raise FileNotFoundError(f"Export presets file not found: {presets_file}")

    content = presets_file.read_text(encoding="utf-8")
    pattern = re.compile(r'\[preset\.(\d+)\]\s*\n(.*?)(?=\n\[preset\.|\Z)', re.DOTALL)
    presets = []

    for match in pattern.finditer(content):
        preset_id = int(match.group(1))
        body = match.group(2)

        name_match = re.search(r'name="([^"]+)"', body)
        platform_match = re.search(r'platform="([^"]+)"', body)
        path_match = re.search(r'export_path="([^"]+)"', body)

        name = name_match.group(1) if name_match else f"Preset_{preset_id}"
        platform = platform_match.group(1) if platform_match else ""
        export_path = path_match.group(1) if path_match else ""

        presets.append({
            "id": preset_id,
            "name": name,
            "platform": platform,
            "export_path": export_path,
        })

    presets.sort(key=lambda x: x["id"])
    return presets


def determine_pck_subpath(preset: dict) -> Path:
    """
    Determines where a PCK file should go under the Data/ folder.
    Levels go to Levels/<filename>.
    Base packs go to <filename>.
    """
    export_path = preset.get("export_path", "")
    preset_name = preset.get("name", "")

    # If the configured export_path already specifies a Data subpath:
    # e.g., "../LS5E3_Build/LS5E3_Structured/Data/Levels/cityescape.pck"
    # or   "../LS5E3_Build/LS5E3_Structured/Data/audio.pck"
    if "Data/" in export_path:
        sub = export_path.split("Data/", 1)[1]
        return Path(sub)
    elif "data/" in export_path:
        sub = export_path.split("data/", 1)[1]
        return Path(sub)

    # Fallback heuristic based on name or filename
    filename = Path(export_path).name if export_path else f"{preset_name}.pck"
    if not filename.endswith(".pck"):
        filename += ".pck"

    is_level = (
        preset_name.lower().startswith("level")
        or "level" in export_path.lower()
        or "level" in filename.lower()
    )

    if is_level:
        return Path("Levels") / filename
    return Path(filename)


def run_command(cmd, dry_run=False, cwd=None):
    """Runs a shell command and raises on error."""
    cmd_str = " ".join(f'"{c}"' if " " in c else c for c in cmd)
    print(f"\n[RUN] {cmd_str}")
    if dry_run:
        return
    res = subprocess.run(cmd, cwd=cwd)
    if res.returncode != 0:
        raise RuntimeError(f"Command failed with exit code {res.returncode}: {cmd_str}")


def make_zip(source_dir: Path, zip_dest: Path, dry_run=False):
    """
    Creates a zip archive from source_dir, preserving file permissions and symlinks.
    Uses system 'zip' command when available, falls back to Python zipfile.
    """
    zip_dest.parent.mkdir(parents=True, exist_ok=True)
    if zip_dest.exists() and not dry_run:
        zip_dest.unlink()

    print(f"[ZIP] Creating archive: {zip_dest} from {source_dir}")
    if dry_run:
        return

    # Try system zip first (best for Linux/macOS permissions & symlinks)
    if shutil.which("zip"):
        # Run zip from inside the source directory so paths are relative
        cmd = ["zip", "-r", "-q", "-y", str(zip_dest.resolve()), "."]
        res = subprocess.run(cmd, cwd=str(source_dir))
        if res.returncode == 0:
            return

    # Fallback to Python zipfile module
    with zipfile.ZipFile(zip_dest, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(source_dir):
            for file in files:
                full_path = Path(root) / file
                rel_path = full_path.relative_to(source_dir)
                zinfo = zipfile.ZipInfo.from_file(full_path, arcname=str(rel_path))

                # Preserve executable bit on Unix
                mode = full_path.stat().st_mode
                if mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
                    zinfo.external_attr = (0o755 << 16) | stat.S_IFREG
                zf.writestr(zinfo, full_path.read_bytes())


def main():
    parser = argparse.ArgumentParser(description="Sonic VANE Godot Build Automation")
    parser.add_argument("--godot", default="godot", help="Path to godot executable")
    parser.add_argument("--project-dir", default=".", help="Godot project root")
    parser.add_argument("--output-dir", default="build", help="Temporary build output directory")
    parser.add_argument("--dist-dir", default="dist", help="Distribution directory for release zips")
    parser.add_argument("--skip-editor-import", action="store_true", help="Skip initial godot --editor --quit pass")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without executing")
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    output_dir = Path(args.output_dir).resolve()
    dist_dir = Path(args.dist_dir).resolve()
    godot_bin = args.godot

    presets_file = project_dir / "export_presets.cfg"
    if not presets_file.exists():
        print(f"Error: {presets_file} not found!", file=sys.stderr)
        sys.exit(1)

    presets = parse_export_presets(presets_file)
    print(f"Loaded {len(presets)} presets from {presets_file}")

    # Identify primary presets
    preset_win = next((p for p in presets if p["id"] == 0 or p["name"] == "Windows Desktop"), None)
    preset_linux = next((p for p in presets if p["id"] == 1 or p["name"] == "Linux"), None)
    preset_mac = next((p for p in presets if p["id"] == 2 or p["name"] == "macOS"), None)
    data_presets = [p for p in presets if p["id"] >= 3]

    print("\n--- Detected Preset Mapping ---")
    print(f"Windows Executable Preset : {preset_win['name'] if preset_win else 'NONE'}")
    print(f"Linux Executable Preset   : {preset_linux['name'] if preset_linux else 'NONE'}")
    print(f"macOS Executable Preset   : {preset_mac['name'] if preset_mac else 'NONE'}")
    print(f"Data & Level PCK Presets  : {len(data_presets)} presets (Presets 3..{presets[-1]['id']})")

    # Prepare directories
    win_dir = output_dir / "windows"
    linux_dir = output_dir / "linux"
    mac_dir = output_dir / "macos"
    mac_temp_dir = output_dir / "macos_temp"
    shared_data_dir = output_dir / "shared_data" / "Data"

    if not args.dry_run:
        dist_dir.mkdir(parents=True, exist_ok=True)
        shared_data_dir.mkdir(parents=True, exist_ok=True)
        win_dir.mkdir(parents=True, exist_ok=True)
        linux_dir.mkdir(parents=True, exist_ok=True)
        mac_dir.mkdir(parents=True, exist_ok=True)
        mac_temp_dir.mkdir(parents=True, exist_ok=True)

    # Step 1: Editor Import Pass
    if not args.skip_editor_import:
        print("\n=== [1/5] Initializing Godot Project & Importing Assets ===")
        run_command([godot_bin, "--headless", "--editor", "--quit"], dry_run=args.dry_run, cwd=str(project_dir))

    # Step 2: Build Executables
    print("\n=== [2/5] Building Executables ===")

    # Windows
    if preset_win:
        win_exe = win_dir / "SonicVANE_WIN.exe"
        print(f"\n--> Exporting Windows Desktop: {win_exe}")
        run_command([
            godot_bin, "--headless", "--export-release",
            preset_win["name"], str(win_exe)
        ], dry_run=args.dry_run, cwd=str(project_dir))

    # Linux
    if preset_linux:
        linux_bin = linux_dir / "SonicVANE_LINUX.x86_64"
        print(f"\n--> Exporting Linux: {linux_bin}")
        run_command([
            godot_bin, "--headless", "--export-release",
            preset_linux["name"], str(linux_bin)
        ], dry_run=args.dry_run, cwd=str(project_dir))
        if not args.dry_run and linux_bin.exists():
            linux_bin.chmod(linux_bin.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    # macOS
    if preset_mac:
        mac_zip = mac_temp_dir / "SonicVANE_MAC.zip"
        print(f"\n--> Exporting macOS: {mac_zip}")
        run_command([
            godot_bin, "--headless", "--export-release",
            preset_mac["name"], str(mac_zip)
        ], dry_run=args.dry_run, cwd=str(project_dir))

        if not args.dry_run and mac_zip.exists():
            # Unzip macOS .app bundle into mac_dir
            print(f"--> Extracting {mac_zip} into {mac_dir}")
            with zipfile.ZipFile(mac_zip, "r") as zf:
                zf.extractall(mac_dir)

    # Step 3: Build Data & Level PCK packages (Preset 3 and down)
    print("\n=== [3/5] Building Shared Data & Level PCK Packages ===")
    for p in data_presets:
        rel_path = determine_pck_subpath(p)
        dest_pck = shared_data_dir / rel_path
        if not args.dry_run:
            dest_pck.parent.mkdir(parents=True, exist_ok=True)

        print(f"\n--> Exporting Pack [{p['id']}] '{p['name']}' -> Data/{rel_path}")
        run_command([
            godot_bin, "--headless", "--export-pack",
            p["name"], str(dest_pck)
        ], dry_run=args.dry_run, cwd=str(project_dir))

    # Ensure empty Mods folder exists in Data/
    mods_dir = shared_data_dir / "Mods"
    if not args.dry_run:
        mods_dir.mkdir(parents=True, exist_ok=True)

    # Step 4: Assemble Platform Folders
    print("\n=== [4/5] Assembling Platform Directories ===")
    for target_dir, name in [(win_dir, "Windows"), (linux_dir, "Linux"), (mac_dir, "macOS")]:
        dest_data = target_dir / "Data"
        print(f"--> Copying Data/ into {name} directory: {dest_data}")
        if not args.dry_run:
            if dest_data.exists():
                shutil.rmtree(dest_data)
            shutil.copytree(shared_data_dir, dest_data)

    # Step 5: Create Release Zips
    print("\n=== [5/5] Creating Distribution Zip Archives ===")
    make_zip(win_dir, dist_dir / "SonicVANE-Windows.zip", dry_run=args.dry_run)
    make_zip(linux_dir, dist_dir / "SonicVANE-Linux.zip", dry_run=args.dry_run)
    make_zip(mac_dir, dist_dir / "SonicVANE-macOS.zip", dry_run=args.dry_run)

    print("\n==========================================")
    print("Build and packaging completed successfully!")
    print(f"Archives generated in: {dist_dir}")
    print(" - SonicVANE-Windows.zip")
    print(" - SonicVANE-Linux.zip")
    print(" - SonicVANE-macOS.zip")
    print("==========================================")


if __name__ == "__main__":
    main()
