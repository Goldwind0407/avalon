"""Prepare an offline release from Flutter's build/web directory."""

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen


FONT_SOURCE = (
    "https://raw.githubusercontent.com/google/fonts/"
    "3be1884c48c3e45b52ecc725676a08f87776373e/ofl/notosanstc/"
)
VOICE_PREFIX = "assets/assets/voice/"
PAGES_FILE_LIMIT = 25 * 2**20


HEADERS = """/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
/login
  ! Cross-Origin-Opener-Policy
  ! Cross-Origin-Embedder-Policy
/login/*
  ! Cross-Origin-Opener-Policy
  ! Cross-Origin-Embedder-Policy
"""


def bundle_font(output: Path) -> None:
    font = "fonts/NotoSansTC.ttf"
    manifest = output / "assets/FontManifest.json"
    families = json.loads(manifest.read_text(encoding="utf-8"))
    for name, source in ((font, "NotoSansTC%5Bwght%5D.ttf"),
                         ("fonts/NotoSansTC-OFL.txt", "OFL.txt")):
        target = output / "assets" / name
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            with urlopen(FONT_SOURCE + source, timeout=60) as response:
                target.write_bytes(response.read())
    if not any(family["family"] == "Noto Sans TC" for family in families):
        families.append({"family": "Noto Sans TC", "fonts": [{"asset": font}]})
        manifest.write_text(json.dumps(families), encoding="utf-8")


def pack_voices(source: Path, target: Path, voices: list[str], version: str):
    groups: dict[str, list[str]] = {}
    pauses = []
    for name in voices:
        persona, separator, _ = name.removeprefix(VOICE_PREFIX).partition("/")
        if separator:
            groups.setdefault(persona, []).append(name)
        else:
            pauses.append(name)
    if not groups:
        raise SystemExit("No NPC voices found")
    groups[min(groups)].extend(pauses)

    index = {}
    pack_paths = []
    for persona, tracks in sorted(groups.items()):
        filename = f"voice-packs/{version}/{persona}.bin"
        pack_paths.append(quote(filename, safe="/"))
        pack = target / filename
        pack.parent.mkdir(parents=True, exist_ok=True)
        with pack.open("wb") as stream:
            for name in tracks:
                data = (source / name).read_bytes()
                if not data:
                    raise SystemExit(f"Empty voice clip: {name}")
                index[quote(name, safe="/")] = [len(pack_paths) - 1, stream.tell(), len(data)]
                stream.write(data)
        if pack.stat().st_size > PAGES_FILE_LIMIT:
            raise SystemExit(f"Voice pack exceeds 25 MiB: {filename}")
    return pack_paths, index


def prepare(output: Path, destination: Path) -> Path:
    if destination.resolve().is_relative_to(output.resolve()):
        raise SystemExit("Publish directory must be outside the Flutter build")
    worker = Path(__file__).with_name("pwa_worker.js").read_text(encoding="utf-8")
    index = output / "index.html"
    html = index.read_text(encoding="utf-8")
    bootstrap = '<script src="flutter_bootstrap.js" async></script>'
    if bootstrap not in html:
        raise SystemExit("Expected the Flutter bootstrap script in build/web/index.html")
    if '<script src="pwa.js"></script>' not in html:
        html = html.replace(bootstrap, '<script src="pwa.js"></script>\n  ' + bootstrap)

    bundle_font(output)
    core, media, voices = [], [], []
    files = []
    core_bytes = media_bytes = voice_bytes = 0
    revision = hashlib.sha256(worker.encode("utf-8"))
    revision.update(Path(__file__).read_bytes())
    revision.update(html.encode("utf-8"))
    voice_revision = hashlib.sha256(b"avalon-packed-mp3-v1")
    for path in sorted(output.rglob("*")):
        if not path.is_file():
            continue
        asset = path.relative_to(output)
        if any(part.startswith(".") for part in asset.parts):
            continue
        relative = asset.as_posix()
        if relative in {"sw.js", "flutter_service_worker.js"} or path.suffix in {".map", ".symbols"}:
            continue
        # skwasm is the WebAssembly renderer the `--wasm` build runs on; wimp
        # is an experimental one Flutter does not load by default
        if relative.startswith("canvaskit/") and path.name.startswith("wimp"):
            continue
        contents = path.read_bytes()
        fingerprint = relative.encode("utf-8") + b"\0" + hashlib.sha256(contents).digest()
        revision.update(fingerprint)
        url = quote(relative, safe="/")
        if relative.startswith(VOICE_PREFIX) and path.suffix.lower() == ".mp3":
            voices.append(relative)
            voice_bytes += len(contents)
            voice_revision.update(fingerprint)
            continue
        files.append(asset)
        # the sign-in page (and the HTML trial, web/proto/) is published, but
        # not kept for playing offline:
        # signing in needs the network anyway, and the offline download
        # takes any web page other than the game's own for an error page
        if relative.startswith(("login/", "proto/")):
            continue
        if relative.startswith("assets/") and path.suffix.lower() in {
            ".avif", ".gif", ".jpeg", ".jpg", ".png", ".svg", ".webp",
            ".aac", ".m4a", ".mp3", ".ogg", ".wav",
        }:
            media.append(url)
            media_bytes += len(contents)
        else:
            core.append(url)
            core_bytes += len(contents)

    required = {
        "index.html", "main.dart.js", "flutter_bootstrap.js", "manifest.json",
        "pwa.js", "pwa.css", "canvaskit/canvaskit.js", "canvaskit/canvaskit.wasm",
        "assets/AssetManifest.bin.json", "assets/FontManifest.json",
        "assets/fonts/NotoSansTC.ttf",
    }
    required_media = {"assets/assets/audio/tap.wav", "assets/assets/images/brand/emblem.webp"}
    missing = sorted(required.difference(core) | required_media.difference(media))
    if not (output / "login/index.html").is_file():
        missing.append("login/index.html")
    if missing:
        raise SystemExit("Missing required offline files: " + ", ".join(missing))
    if not voices:
        raise SystemExit("NPC audio assets are missing from the Flutter build")
    version = revision.hexdigest()[:16]
    voice_version = voice_revision.hexdigest()[:16]
    publish = destination / version
    if (publish / "sw.js").is_file():
        return publish
    for asset in files:
        target = publish / asset
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(output / asset, target)
    # the release is shown on the menu (web/pwa.js) and sent with the
    # frame-rate reports, so an old copy is told from a new one at a glance
    shown = html.replace('<script src="pwa.js"></script>',
                         f'<script>window.avalonRelease = "{version}";</script>\n  '
                         '<script src="pwa.js"></script>')
    (publish / "index.html").write_text(shown, encoding="utf-8")
    packs, voice_index = pack_voices(output, publish, voices, voice_version)
    config = {"version": version, "core": core, "coreBytes": core_bytes,
              "media": media, "mediaBytes": media_bytes,
              "voicePacks": packs, "voiceIndex": voice_index, "voiceBytes": voice_bytes,
              "voiceVersion": voice_version}
    # Cloudflare Pages headers: the game page is isolated from other sites,
    # which lets the WebAssembly renderer draw on several threads; the
    # sign-in page is not, so Google's sign-in window can report back.
    (publish / "_headers").write_text(HEADERS, encoding="utf-8")
    worker_path = publish / "sw.js"
    temporary_worker = worker_path.with_suffix(".tmp")
    temporary_worker.write_text(
        "const release = " + json.dumps(config, separators=(",", ":")) + ";\n" + worker,
        encoding="utf-8",
    )
    temporary_worker.replace(worker_path)
    wasm = "main.dart.wasm" in core
    print(f"Offline release {config['version']} ({'WebAssembly + JavaScript' if wasm else 'JavaScript only'}): "
          f"{len(core)} core files ({core_bytes / 2**20:.1f} MiB), "
          f"{len(media)} game media ({media_bytes / 2**20:.1f} MiB), "
          f"{len(voices)} clips in {len(packs)} packs ({voice_bytes / 2**20:.1f} MiB)",
          file=sys.stderr)
    return publish


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", nargs="?", type=Path, default=Path("build/web"))
    parser.add_argument("--destination", type=Path, default=Path("build/pwa"))
    args = parser.parse_args()
    print(prepare(args.build, args.destination).as_posix())
