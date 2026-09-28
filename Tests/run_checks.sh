#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONDONTWRITEBYTECODE=1
python3 -m unittest discover -s Tests -v
check_dir=$(mktemp -d /tmp/cottage-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
python3 - "$check_dir" <<'PY'
import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('fixture','Tests/test_catalog_builder.py')
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
root=Path(sys.argv[1])
pack=root/'Artists/Example/Collection/01.Pack'
pack.mkdir(parents=True)
(root/'Artists/Example/Example.txt').write_text('Display Name: Example\nDescription: Test art\nUsage: Fixture use only.\n')
(root/'Artists/Example/Artist image.png').write_bytes(m.png())
(pack/'01.Image.png').write_bytes(m.png(1200, 800))
(root/'image.png').write_bytes(m.png(1200, 800))
(root/'catalog.json').write_text(json.dumps(m.catalog.build(root,'example/artists','main')))
PY
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" -module-cache-path "$check_dir/modules" \
  App/CottageShared/CottageCatalog.swift \
  App/CottageShared/CottageSharedContainer.swift \
  App/CottageShared/CottageDownloads.swift \
  App/Cottage/Services/CottageServiceConfiguration.swift \
  App/Cottage/Services/CottageCatalogRepository.swift \
  Tests/CatalogChecks.swift -o "$check_dir/checks"
"$check_dir/checks" "$check_dir/catalog.json"
