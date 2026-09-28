#!/usr/bin/env python3
"""Build the app's catalog from artist folders. Local only: never uploads or publishes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
from urllib.parse import quote, urlparse


def title(name):
    return re.sub(r"^\d+[. _-]+", "", name)


def order(path):
    return [int(part) if part.isdigit() else part.casefold()
            for part in re.split(r"(\d+)", path.name)]


def identity(path):
    return "/".join(title(part) for part in path.parts)


def png_size(path, max_bytes, max_side, max_pixels):
    data = path.read_bytes()
    if len(data) > max_bytes or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"{path}: expected a PNG no larger than {max_bytes:,} bytes")
    width, height = struct.unpack(">II", data[16:24])
    if not (0 < width <= max_side and 0 < height <= max_side and width * height <= max_pixels):
        raise ValueError(f"{path}: image dimensions exceed this pack's limits")
    return hashlib.sha256(data).hexdigest()


def profile(path):
    fields = {"Name": "", "Display Name": "", "Description": "", "Usage": "", "Link": []}
    section = None
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        key, separator, value = line.partition(":")
        if section != "Usage" and separator and key in fields:
            section = key
            if key == "Link":
                url = urlparse(value.strip())
                if url.scheme != "https" or not url.netloc:
                    raise ValueError(f"{path}: links must start with https://")
                fields[key].append(value.strip())
            else:
                fields[key] = value.strip()
        elif section in ("Description", "Usage"):
            fields[section] += "\n" + line
        elif line.strip():
            raise ValueError(f"{path}: unrecognized profile line: {line}")
    for key in ("Display Name", "Description", "Usage"):
        fields[key] = fields[key].strip()
        if not fields[key] or re.search(r"\[(Replace|Specify)", fields[key]):
            raise ValueError(f"{path}: fill in {key} before publication")
    return fields


def build(root, repository, ref):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) or ".." in repository:
        raise ValueError("Repository must be owner/repository")
    artists_root = root / "Artists"
    if not artists_root.is_dir():
        raise ValueError(f"Missing {artists_root}; refusing to produce an empty removal catalog")
    if any(path.is_symlink() for path in artists_root.rglob("*")):
        raise ValueError("Artist submissions must not contain symbolic links")
    base = f"https://raw.githubusercontent.com/{repository}/{quote(ref, safe='')}"

    def url(path, checksum):
        return f"{base}/{quote(path.relative_to(root).as_posix(), safe='/')}?v={checksum}"

    artists, artworks = [], []
    for folder in sorted((p for p in artists_root.iterdir() if p.is_dir() and not p.name.startswith('.')), key=order):
        fields = profile(folder / f"{folder.name}.txt")
        artist_id = identity(folder.relative_to(artists_root))
        banner = folder / "Artist image.png"
        banner_url = url(banner, png_size(banner, 2_000_000, 4096, 16_000_000)) if banner.exists() else None
        approved = fields["Usage"] != "Pending artist confirmation."
        artists.append(dict(
            id=artist_id, slug=folder.name, displayName=fields["Display Name"],
            biography=fields["Description"], usage=fields["Usage"], headerURL=banner_url,
            links=[dict(id=link, kind="social", url=link) for link in dict.fromkeys(fields["Link"])],
        ))
        for collection in sorted((p for p in folder.iterdir() if p.is_dir() and not p.name.startswith('.')), key=order):
            for pack in sorted((p for p in collection.iterdir() if p.is_dir() and not p.name.startswith('.')), key=order):
                images = sorted((p for p in pack.iterdir() if p.suffix.lower() == ".png"), key=order)
                if not images:
                    continue
                if len(images) > 200:
                    raise ValueError(f"{pack}: at most 200 images per pack")
                kind = "sticker_pack"
                if (pack / "Pack.txt").exists():
                    setting = (pack / "Pack.txt").read_text().strip()
                    if setting not in ("Type: wallpaper", "Type: sticker_pack"):
                        raise ValueError(f"{pack}/Pack.txt: use Type: wallpaper or Type: sticker_pack")
                    kind = setting.removeprefix("Type: ")
                files = []
                for image in images:
                    limits = (20_000_000, 8192, 40_000_000)
                    checksum = png_size(image, *limits)
                    files.append(dict(id=identity(image.relative_to(artists_root)), title=title(image.stem), url=url(image, checksum), sha256=checksum))
                if len({f['id'] for f in files}) != len(files):
                    raise ValueError(f"{pack}: duplicate image identities after removing numbering")
                artworks.append(dict(
                    id=identity(pack.relative_to(artists_root)), title=title(pack.name),
                    collectionTitle=title(collection.name), summary=fields["Description"], kind=kind,
                    credits=[dict(artistID=artist_id, role="artist")], previewURL=files[0]["url"],
                    deliveryKind="cottage" if approved else "planned",
                    usageLicense="artist_specified" if approved else "unspecified", itemCount=len(files), files=files,
                    order=len(artworks),
                ))
    if len({a['id'] for a in artists}) != len(artists) or len({a['id'] for a in artworks}) != len(artworks):
        raise ValueError("Duplicate artist or pack identities after removing numbering")
    return dict(version=1, artists=artists, artworks=artworks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Content repository folder containing Artists/")
    parser.add_argument("--repository", required=True, help="owner/repository")
    parser.add_argument("--ref", default="main", help="Branch, tag, or commit containing the artwork")
    parser.add_argument("--output", type=Path, help="Defaults to ROOT/catalog.json")
    args = parser.parse_args()
    try:
        result = build(args.root, args.repository, args.ref)
        data = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        if len(data.encode()) > 2_000_000:
            raise ValueError("Catalog exceeds the app's 2 MB limit")
        output = args.output or args.root / "catalog.json"
        temporary = output.with_suffix(".tmp")
        temporary.write_text(data, encoding="utf-8")
        temporary.replace(output)
        print(f"Wrote {output}: {len(result['artists'])} artists, {len(result['artworks'])} packs")
    except (ValueError, OSError, struct.error) as error:
        parser.exit(1, f"Catalog not written: {error}\n")


if __name__ == "__main__":
    main()
