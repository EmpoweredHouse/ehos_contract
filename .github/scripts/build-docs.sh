#!/usr/bin/env bash
# Builds the documentation of the four packages into one directory: ExDoc's HTML,
# the Markdown it is made from, and an index linking them. Run by
# .github/workflows/docs.yml, and by hand from anywhere in the repository:
#
#   .github/scripts/build-docs.sh /tmp/eh-os-contract-docs "$(git rev-parse --abbrev-ref HEAD)"
#
# Dependencies must be fetched first (`mix deps.get`; `--only test` for the
# engine, the dashboard, the credential verifier and the graph renderer, whose `:dev` dependencies are private). The build runs under MIX_ENV=test,
# as the gate's `docs --warnings-as-errors` does, so it needs no database and no
# credential, and fails on the same broken references the gate fails on.
#
# The output directory is replaced, so it must not exist, be empty, or hold an earlier
# build of this script: anything else is refused rather than deleted.
set -euo pipefail

usage="usage: build-docs.sh <output directory> <ref>"
out="${1:?$usage}"
ref="${2:?$usage}"
root="$(git rev-parse --show-toplevel)"
sha="$(git -C "$root" rev-parse HEAD)"
marker=".eh-os-contract-docs"

# The ref is written into the index page: a branch's, tag's or commit's name only.
if [[ ! "$ref" =~ ^[A-Za-z0-9._/][A-Za-z0-9._/-]*$ || "$ref" == *..* ]]; then
  echo "build-docs.sh: '$ref' is not a branch, tag or commit name" >&2
  exit 1
fi

if [[ -e "$out" && ! -f "$out/$marker" && -n "$(ls -A "$out" 2>/dev/null)" ]]; then
  echo "build-docs.sh: $out exists and is not an earlier build; name a new directory" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out/html" "$out/markdown"
out="$(cd "$out" && pwd)"
touch "$out/$marker"

version() {
  local v
  v="$(sed -n 's/^  @version "\(.*\)"$/\1/p' "$root/packages/$1/mix.exs" | head -n 1)"
  if [[ -z "$v" ]]; then
    echo "build-docs.sh: no @version in packages/$1/mix.exs" >&2
    exit 1
  fi
  echo "$v"
}

engine_version="$(version eh_os_contract)"
web_version="$(version eh_os_contract_web)"
auth_version="$(version eh_os_contract_auth)"
graph_version="$(version eh_os_contract_graph)"

# Each package under the short name the archive uses.
names=(engine web auth graph)
packages=(eh_os_contract eh_os_contract_web eh_os_contract_auth eh_os_contract_graph)

for i in "${!names[@]}"; do
  name="${names[$i]}"
  package="packages/${packages[$i]}"

  # "View source" links to the commit built, not to a version tag that may not exist.
  (cd "$root/$package" &&
    EH_OS_CONTRACT_DOCS_SOURCE_REF="$sha" MIX_ENV=test \
      mix docs -f html --warnings-as-errors --output "$out/html/$name")

  mkdir -p "$out/markdown/$name"
  cp "$root/$package/README.md" "$root/$package/CHANGELOG.md" "$out/markdown/$name/"
  if [ -d "$root/$package/docs" ]; then
    cp -R "$root/$package/docs" "$out/markdown/$name/docs"
  fi
done

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
<p>Built from <code>${ref}</code> at <code>${sha:0:7}</code>.</p>
<ul>
  <li><a href="html/engine/index.html">eh_os_contract</a> ${engine_version}: the engine, its guides and the DSL reference</li>
  <li><a href="html/web/index.html">eh_os_contract_web</a> ${web_version}: the dashboard</li>
  <li><a href="html/auth/index.html">eh_os_contract_auth</a> ${auth_version}: EHOS credentials and sign-in</li>
  <li><a href="html/graph/index.html">eh_os_contract_graph</a> ${graph_version}: the graph renderer</li>
</ul>
<p>The Markdown the pages are made from, as committed, is in <code>markdown/</code>.</p>
</body>
</html>
HTML

echo "documentation of ${ref} (${sha:0:7}) in ${out}"
