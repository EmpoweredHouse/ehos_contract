#!/usr/bin/env bash
# Builds the documentation of the three packages into one directory: ExDoc's HTML,
# the Markdown it is made from, and an index linking them. Run by
# .github/workflows/docs.yml, and by hand from the repository's root:
#
#   .github/scripts/build-docs.sh /tmp/docs "$(git rev-parse --abbrev-ref HEAD)"
#
# Dependencies must be fetched first (`mix deps.get`; `--only test` for the
# dashboard, whose `:dev` dependency is private). The build runs under MIX_ENV=test,
# as the gate's `docs --warnings-as-errors` does, so it needs no database and no
# credential, and fails on the same broken references the gate fails on.
set -euo pipefail

out="${1:?usage: build-docs.sh <output directory> <ref>}"
ref="${2:?usage: build-docs.sh <output directory> <ref>}"
root="$(pwd)"
sha="$(git rev-parse --short HEAD)"

# The ref is written into the index page and the archive's name: a branch's, a tag's
# or a commit's characters only.
if [[ ! "$ref" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "build-docs.sh: '$ref' is not a branch, tag or commit name" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out/html" "$out/markdown"
out="$(cd "$out" && pwd)"

# Each package under the short name the archive uses.
names=(engine web auth)
packages=(eh_os_contract eh_os_contract_web eh_os_contract_auth)

for i in "${!names[@]}"; do
  name="${names[$i]}"
  package="packages/${packages[$i]}"

  (cd "$root/$package" && MIX_ENV=test mix docs -f html --warnings-as-errors --output "$out/html/$name")

  mkdir -p "$out/markdown/$name"
  cp "$root/$package/README.md" "$root/$package/CHANGELOG.md" "$out/markdown/$name/"
  if [ -d "$root/$package/docs" ]; then
    cp -R "$root/$package/docs" "$out/markdown/$name/docs"
  fi
done

version() {
  sed -n 's/^  @version "\(.*\)"$/\1/p' "$root/packages/$1/mix.exs" | head -n 1
}

cat > "$out/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>eh_os_contract documentation</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 40rem; margin: 3rem auto; padding: 0 1rem; color: #222; background: #fff; }
  code { font-size: 0.9em; }
  li { margin: 0.4rem 0; }
  @media (prefers-color-scheme: dark) { body { color: #ddd; background: #161616; } a { color: #8ab4f8; } }
</style>
</head>
<body>
<h1>eh_os_contract documentation</h1>
<p>Built from <code>${ref}</code> at <code>${sha}</code>.</p>
<ul>
  <li><a href="html/engine/index.html">eh_os_contract</a> $(version eh_os_contract): the engine, its guides and the DSL reference</li>
  <li><a href="html/web/index.html">eh_os_contract_web</a> $(version eh_os_contract_web): the dashboard</li>
  <li><a href="html/auth/index.html">eh_os_contract_auth</a> $(version eh_os_contract_auth): EHOS credentials and sign-in</li>
</ul>
<p>The Markdown the pages are made from, as committed, is in <code>markdown/</code>.</p>
</body>
</html>
HTML

echo "documentation of ${ref} (${sha}) in ${out}"
