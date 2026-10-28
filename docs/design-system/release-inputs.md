# Verify retained inputs against actual published archives

`tool/design-system/verify_release_inputs.py` reconstructs every package snapshot
in `tool/design-system/sources.lock.json` from its integrity-verified public npm
archive. It calls the existing `published.verify_snapshot` decoder for each
locked package. This checks the actual CSS, class exports, behavior snapshots,
theme injection order, fonts, manifests and licenses required by that decoder;
no package JavaScript, install scripts or package-manager commands are executed.

The source inventory and lock agreeing with one another is insufficient: both
are editable. This check reads the released archive and reproduces its retained
inputs independently. It applies to the locked subset, currently 13 releases
and 83 retained files. It does not mean that all upstream packages are retained,
all source component states are translated, or all visual comparisons passed.
The separate [source inventory](source-inventory.md) accounts for the larger
source universe and explicitly pending inputs.

## Inputs and identity

Before reading any archive, the verifier validates the source inventory's
snapshot bindings, the current lock digest, all retained-file hashes and package
manifest identities. It binds each locked name/version, tarball and SHA-512
integrity to the corresponding frozen inventory publication record. The allowed
fetch URL is computed from that exact public npm package/version identity and
must equal the locked URL. The inventory's immutable npm version endpoint must
refer to that same identity. Arbitrary URLs, credentials in URLs, queries,
alternate versions, redirects and file URLs are rejected.

Each archive is checked against its locked SHA-512 integrity before parsing.
The archive's unique regular `package/package.json` must have the exact
name/version and published dependency declarations recorded in the inventory.
The existing decoder then reconstructs and compares the retained inputs.
Archive hashes are checked again afterward, so a successful receipt also states
that the archive stayed unchanged through reconstruction.

The verifier makes direct public HTTPS requests with no npm credential file,
proxy credentials, cookie jar or authorization header. It never installs a
package or executes the archive's JavaScript. It does not refresh the source pin,
inventory publication metadata or source lock.

## Run with a persistent cache

On k172, source the existing absolute `scripts/pr16-env.sh` environment before
running Python. Supply an owned persistent cache directory; the default is the
repository's `.local/release-input-archives`, or `DSH_RELEASE_CACHE` if set.

```sh
python3 -B tool/design-system/verify_release_inputs.py \
  --cache-dir "$DSH_RELEASE_CACHE" --receipt "$RELEASE_INPUT_RECEIPT"
```

Only missing archives are downloaded. Cache names include the full package name
and exact release version. The response goes to a private temporary file in
that same cache directory, is flushed and integrity-checked, then becomes the
complete cache entry atomically. Publication does not overwrite an entry another
process installed meanwhile. Interrupted or incorrect downloads leave no final
entry; only the verifier's own temporary file is removed.

An existing cache entry is always revalidated. Corrupt bytes cause a clear
failure, remain available for inspection and are never silently replaced by a
download. Repair or remove that specific entry explicitly after investigating;
the next non-offline run can fetch it if missing. Cache-file symlinks are refused.
Unrelated SDKs, Node/DSH runtimes, other archives and other agents' caches are
not discovered, modified or cleaned by this tool.

To require cached archives exclusively:

```sh
python3 -B tool/design-system/verify_release_inputs.py \
  --cache-dir "$DSH_RELEASE_CACHE" --offline --receipt "$RELEASE_INPUT_RECEIPT"
```

`--offline` performs no network access, still verifies every archive's integrity
and still reconstructs every locked snapshot. A missing archive fails. It needs
no DSH source checkout: the independent release inputs are the cached archives.
It does not independently refresh the registry's publication metadata.

## Receipts and integration

`--receipt` atomically writes JSON only after every locked package passes.
Receipts include the source pin, lock/inventory hashes, verifier/decoder hashes,
start/completion times, archive SHA-256 and SHA-512 identities, cache/download
origin, per-package reconstruction results and totals. Verifier/input hashes are
bound before reconstruction and must remain unchanged afterward; retained files
are rechecked before success. File names are relative;
receipts contain no machine-specific cache path or credential. There is no
partial success receipt. Callers must honor the command's exit status and bind
the receipt's hashes to the checked source rather than reuse an older receipt.

```sh
python3 -B -m unittest discover -s tool/tests -p test_release_inputs.py -v
```

Focused tests cover corrupt caches without replacement, missing offline inputs,
atomic installation, interrupted/wrong downloads, concurrent bad entries,
archive identity/dependency mismatches, restricted URLs/redirects, snapshot
drift and complete-success receipts. The central reconstruction negative changes
local CSS and rehashes both editable records; archive reconstruction must still
reject the changed CSS. These tests use small local tar fixtures and require no
network, source checkout or package runtime. Integration into preflight and CI
is owned by the design-system contract.
