defmodule EhOsContract.GraphRenderer.AssetsTest do
  # What a host loads, held to its Content-Security-Policy of `default-src 'self'` as far
  # as reading the files can: no `style` attribute, no inline `<style>`, no `eval`. A
  # browser sees more — the prototype's three defects passed every check of this kind —
  # so each change to the drawing layer is also looked at in one (docs/adr/graph-renderer.md).
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @hook Path.join(@root, "assets/js/eh_os_contract_graph.js")
  @bundle Path.join(@root, "priv/static/eh_os_contract_graph.esm.js")
  @stylesheet Path.join(@root, "priv/static/eh_os_contract_graph.css")

  # The hook's code without its comments, which name what it must not do. The `//` of a URL
  # in a string (the SVG namespace) follows a colon and stays.
  defp code(path) do
    path
    |> File.read!()
    |> String.replace(~r{/\*.*?\*/}s, "")
    |> String.replace(~r{(^|[^:])//.*$}m, "\\1")
  end

  test "the hook never writes a style or markup, only classes and the constructed stylesheets" do
    source = code(@hook)

    # The word itself, so that no spelling slips past: `setAttribute('style', …)`, an SVG
    # helper given a `style:` key, `setAttributeNS(null, "style", …)`, `el.style.x`.
    refute source =~ ~r/\bstyle\b/, "assets/js/eh_os_contract_graph.js names a style in its code"

    for forbidden <- [
          "attributeStyleMap",
          "cssText",
          "innerHTML",
          "outerHTML",
          "insertAdjacentHTML",
          "document.write",
          "eval(",
          "new Function"
        ] do
      refute source =~ forbidden, "assets/js/eh_os_contract_graph.js uses #{forbidden}"
    end

    assert source =~ "new CSSStyleSheet()"
    assert source =~ "adoptedStyleSheets"
  end

  test "the committed bundle exports the hook and injects no stylesheet or code" do
    bundle = File.read!(@bundle)

    assert bundle =~ ~r/export\s*\{[^}]*EhOsContractGraph/

    for forbidden <- [
          ~s{createElement("style")},
          "<style",
          ~s{setAttribute("style"},
          "eval(",
          "new Function("
        ] do
      refute bundle =~ forbidden, "priv/static/eh_os_contract_graph.esm.js has #{forbidden}"
    end
  end

  test "the stylesheet loads nothing from anywhere, and defines only its own custom properties" do
    css = File.read!(@stylesheet)

    refute css =~ "@import"
    refute css =~ "url("

    for [name] <- Regex.scan(~r/(--[a-z0-9-]+)\s*:/, css, capture: :all_but_first),
        do: assert(String.starts_with?(name, "--eh-os-contract-graph-"), name)
  end

  test "NOTICE names each vendored library the bundle carries" do
    notice = File.read!(Path.join(@root, "NOTICE"))

    for file <- File.ls!(Path.join(@root, "assets/vendor")),
        do: assert(notice =~ "assets/vendor/#{file}", "NOTICE does not name #{file}")
  end
end
