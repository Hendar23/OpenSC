"""Package a clean game project or export a standalone Windows game."""
import argparse
import json
import re
import shutil
import subprocess
import struct
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "godot"
TEXT_TYPES = {".gd", ".gdshader", ".gdshaderinc", ".tscn", ".tres", ".godot"}


def build(destination: Path, archive_output: bool = True) -> dict:
    if destination.exists():
        raise SystemExit(f"Refusing to overwrite an existing folder: {destination}")
    files = {Path("project.godot"), Path("game.tscn"), Path("input_bindings.gd")}
    files.update(Path(name) for name in ("submarine_tuning.cfg", "submarine_audio.cfg", "view_defaults.cfg"))
    files.update(p.relative_to(PROJECT) for p in (PROJECT / "game_assets").rglob("*") if p.is_file() and p.suffix != ".import")
    pending = list(files)
    while pending:
        relative = pending.pop()
        source = PROJECT / relative
        if source.suffix not in TEXT_TYPES:
            continue
        for match in re.finditer(r'["\']res://([^"\'\r\n]+)["\']', source.read_text(encoding="utf-8")):
            candidate = Path(match.group(1))
            if ".." in candidate.parts or not (PROJECT / candidate).is_file():
                continue  # External map/mod folders and runtime output are handled separately.
            if candidate not in files:
                files.add(candidate)
                pending.append(candidate)
    for relative in sorted(files):
        source = PROJECT / relative
        target = destination / "godot" / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        uid = source.with_name(source.name + ".uid")
        if uid.is_file():
            shutil.copy2(uid, target.with_name(target.name + ".uid"))
    (destination / "Maps").mkdir()
    shutil.copy2(ROOT / "Maps" / "scen1.json", destination / "Maps" / "scen1.json")
    (destination / "Mods").mkdir()
    bundled_mods = []
    for pack in sorted((ROOT / "Mods").iterdir()):
        if not pack.is_dir() or not (pack / "mod.json").is_file():
            continue
        manifest = json.loads((pack / "mod.json").read_text(encoding="utf-8"))
        for entry in manifest.get("assets", {}).values():
            relative = entry if isinstance(entry, str) else entry["file"]
            asset = (pack / relative).resolve()
            if not asset.is_relative_to(pack.resolve()) or not asset.is_file():
                raise SystemExit(f"Missing or invalid mod asset: {pack.name}/{relative}")
        shutil.copytree(pack, destination / "Mods" / pack.name,
                        ignore=shutil.ignore_patterns(".*", "*.import", "*.tmp", "*.bak"))
        bundled_mods.append(manifest["id"])
    shutil.copy2(ROOT / "Launch Game.cmd", destination / "Launch Game.cmd")
    # Archive before running Godot: imports, personal files and verification
    # output must never become part of the distributable.
    archive = destination.parent / (destination.name + ".zip")
    if archive_output:
        archive_folder(destination, archive)
    report = {"folder": str(destination), "archive": str(archive), "runtime_scripts": len([p for p in files if p.suffix == ".gd"]), "files": len([p for p in destination.rglob("*") if p.is_file()]), "mods": bundled_mods, "editor_included": (destination / "godot/asset_editor.gd").exists()}
    return report


def archive_folder(folder: Path, archive: Path) -> None:
    with ZipFile(archive, "w", ZIP_DEFLATED) as zipped:
        for path in sorted(folder.rglob("*")):
            zipped.write(path, Path(folder.name) / path.relative_to(folder))


def stamp_windows_version(executable: Path, version: str) -> None:
    """Write the same display version to Windows' standard version resource."""
    import ctypes
    from ctypes import wintypes

    def block(key, value=b"", children=b"", kind=1, length=None):
        data = b"\0" * 6 + (key + "\0").encode("utf-16le")
        data += b"\0" * (-len(data) % 4)
        data += value
        if children:
            data += b"\0" * (-len(data) % 4) + children
        value_length = len(value) // 2 if kind else len(value)
        return struct.pack("<HHH", len(data), value_length if length is None else length, kind) + data[6:]

    def siblings(items):
        data = b""
        for item in items:
            data += b"\0" * (-len(data) % 4) + item
        return data

    numbers = [int(n) for n in version.split("-", 1)[0].split(".")]
    numbers += [int(version.rsplit(".", 1)[1]) if "-" in version else 0]
    high, low = numbers[0] << 16 | numbers[1], numbers[2] << 16 | numbers[3]
    fixed = struct.pack("<13I", 0xFEEF04BD, 0x10000, high, low, high, low,
                        0x3F, 2 if "-" in version else 0, 0x40004, 1, 0, 0, 0)
    values = {"FileVersion": version, "ProductVersion": version, "ProductName": "OpenSC",
              "FileDescription": "OpenSC", "InternalName": "OpenSC", "OriginalFilename": "OpenSC.exe"}
    strings = siblings([block(key, (value + "\0").encode("utf-16le")) for key, value in values.items()])
    children = siblings([block("StringFileInfo", children=block("040904B0", children=strings)),
                         block("VarFileInfo", children=block("Translation", struct.pack("<HH", 0x409, 1200), kind=0))])
    resource = block("VS_VERSION_INFO", fixed, children, kind=0)
    api = ctypes.WinDLL("kernel32", use_last_error=True)
    api.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    api.BeginUpdateResourceW.restype = wintypes.HANDLE
    api.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p, wintypes.DWORD]
    api.UpdateResourceW.restype = wintypes.BOOL
    api.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    api.EndUpdateResourceW.restype = wintypes.BOOL
    handle = api.BeginUpdateResourceW(str(executable), False)
    if not handle: raise ctypes.WinError(ctypes.get_last_error())
    buffer = ctypes.create_string_buffer(resource)
    if not api.UpdateResourceW(handle, ctypes.c_void_p(16), ctypes.c_void_p(1), 0x409, buffer, len(resource)):
        error = ctypes.get_last_error(); api.EndUpdateResourceW(handle, True)
        raise ctypes.WinError(error)
    if not api.EndUpdateResourceW(handle, False): raise ctypes.WinError(ctypes.get_last_error())


def standalone(destination: Path, engine: Path, template: Path) -> dict:
    if destination.exists():
        raise SystemExit(f"Refusing to overwrite an existing folder: {destination}")
    stage = destination.with_name(destination.name + "-build")
    report = build(stage, archive_output=False)
    destination.mkdir()
    for name in ("Maps", "Mods"):
        shutil.copytree(stage / name, destination / name)
    for name in ("GODOT_LICENSE.txt", "GODOT_COPYRIGHT.txt"):
        shutil.copy2(template.parent / name, destination / name)
    preset = '''[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="*.cfg"
exclude_filter=""
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=%s
debug/export_console_wrapper=0
binary_format/architecture="x86_64"
binary_format/embed_pck=false
application/modify_resources=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
''' % json.dumps(template.as_posix())
    (stage / "godot/export_presets.cfg").write_text(preset, encoding="utf-8")
    flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    common = [str(engine), "--headless", "--path", str(stage / "godot")]
    for label, args in [("import", ["--editor", "--import"]),
                        ("export", ["--export-release", "Windows Desktop", str(destination / "OpenSC.exe")])]:
        with (stage / (label + ".log")).open("w", encoding="utf-8") as log:
            subprocess.run(common + args, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=180, creationflags=flags)
        if "ERROR:" in (stage / (label + ".log")).read_text(encoding="utf-8", errors="replace"):
            raise SystemExit(f"Godot reported errors during {label}; see {stage / (label + '.log')}")
    if not (destination / "OpenSC.exe").is_file() or not (destination / "OpenSC.pck").is_file():
        raise SystemExit("Godot did not produce the executable and resource pack")
    version = re.search(r'^config/version="([^"]+)"', (stage / "godot/project.godot").read_text(), re.MULTILINE).group(1)
    stamp_windows_version(destination / "OpenSC.exe", version)
    archive = destination.parent / (destination.name + ".zip")
    archive_folder(destination, archive)
    return {"folder": str(destination), "archive": str(archive),
            "mods": report["mods"], "executable": str(destination / "OpenSC.exe"),
            "editor_included": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / ("OpenSC-clean-test-" + datetime.now().strftime("%Y%m%d-%H%M%S")))
    parser.add_argument("--engine", type=Path, help="Export a standalone Windows game using this Godot executable")
    parser.add_argument("--windows-template", type=Path, help="Matching windows_release_x86_64.exe export template")
    args = parser.parse_args()
    if args.engine and not args.windows_template:
        parser.error("--engine requires --windows-template")
    result = standalone(args.output.resolve(), args.engine.resolve(), args.windows_template.resolve()) if args.engine else build(args.output.resolve())
    print(json.dumps(result, indent=2))
