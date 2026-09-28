# The Cottage

The Cottage is a free, artist-first iOS app for artwork and iMessage stickers. This repository holds the app and the public artist catalog it reads.

The app is free. There are no paid packs, in-app purchases, or submission fees. Artwork belongs to the artists who made it; follow each artist's Usage section. Valid DMCA takedown notices will be honored.

## Repository

- `App/` — iOS app and Messages extension (`cottage.xcodeproj`).
- `Artists/` — artist profiles and artwork.
- `Templates/Artist-Submission/` — submission template for new artists.
- `Scripts/build_catalog.py` — validates artist folders and builds `catalog.json`.
- `Tests/` — catalog and download checks.
- `catalog.json` — the index the app reads.

The [MIT license](LICENSE) covers the app code and scripts only. **It does not cover the artwork in `Artists/`.** See [Artists/README.md](Artists/README.md).

## How the app gets content

The app ships with no artists or artwork. On launch it downloads `catalog.json` from `Anqui3tas/Cottage` on `main` (set in `App/Cottage/Services/CottageServiceConfiguration.swift`) and saves it for offline use. It checks again when opened, at most once an hour, or on pull-to-refresh.

Artwork is downloaded only when someone adds a pack, verified against its checksum, and shared with Messages through the App Group. Artwork removed from the catalog is also removed from the app on the next update. Copies already sent can't be recalled.

## Updating the catalog

After adding or changing artist folders:

```sh
python3 Scripts/build_catalog.py . --repository Anqui3tas/Cottage
```

Commit the updated `catalog.json` along with the artwork. Artists with `Usage: Pending artist confirmation.` are listed, but their packs can't be downloaded until usage terms are added.

## Building

Open `App/cottage.xcodeproj`, select the `cottage` scheme, and set up signing. Identifiers: `com.lanteacorp.cottage`, `com.lanteacorp.cottage.MessagesExtension`, App Group `group.com.lanteacorp.cottage`.

```sh
bash Tests/run_checks.sh
```

Shared downloads between the app and Messages need a signed device build to test.
