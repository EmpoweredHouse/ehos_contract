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

  # docs/adr/graph-renderer.md, amendment of 8 October 2026: WebKit styles the whole page again whenever a
  # stylesheet changes, so what changes on every frame is a Web Animation, and a stylesheet is written only when
  # the layout or the canvas's size changes, or when a drag of the panel's edge ends.
  test "what moves on every frame is a Web Animation, not a stylesheet" do
    source = code(@hook)

    assert source =~ ".animate(", "the hook holds no value in a Web Animation"
    assert source =~ "setKeyframes(", "the hook sets an animation's value again in no other way"

    [zoomed] = Regex.run(~r/^  zoomed\(at\) \{.*?^  \},/ms, source)
    refute zoomed =~ "replaceSync", "a zoom writes a stylesheet on every frame"

    [move] = Regex.run(~r/const move = \(e\) => \{.*?^    \}/ms, source)
    refute move =~ "replaceSync", "a drag of the panel's edge writes a stylesheet on every move"
    refute move =~ "panelWidth(", "a drag of the panel's edge writes a stylesheet on every move"
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

  test "every rule of the stylesheet reaches only the package's own elements" do
    css = Regex.replace(~r{/\*.*?\*/}s, File.read!(@stylesheet), "")

    # Each rule with its declarations; an at-rule's own condition is not a rule.
    rules =
      for [selectors, body] <-
            Regex.scan(~r/([^{};]+)\{([^{}]*)\}/, css, capture: :all_but_first),
          selectors = String.trim(selectors),
          not String.starts_with?(selectors, "@"),
          do: {selectors, body}

    # A class of the package, `.ehg` or `.ehg-*`, on an element or on its own.
    own = ~r/\.ehg(?:-[\w-]+)?(?![\w-])/
    # The same class, then a descendant or a child: what follows is inside the package's element.
    inside = ~r/\.ehg(?:-[\w-]+)?(?![\w-])[^\s>]*\s*[\s>]\s*\S/

    for {selectors, body} <- rules,
        # What a pseudo-class or an attribute takes as its argument is not where a rule
        # reaches: `:not(.ehg)` and `[class~=ehg]` say nothing of that.
        bare = selectors |> strip(~r/\[[^\[\]]*\]/, "[]") |> strip(~r/\([^()]*\)/, "()"),
        selector <- bare |> String.split(",") |> Enum.map(&String.trim/1) do
      if selector == ":root" do
        # The page's root may hold only the package's own custom properties.
        for [name] <- Regex.scan(~r/([\w-]+)\s*:/, body, capture: :all_but_first),
            do: assert(String.starts_with?(name, "--eh-os-contract-graph-"), ":root sets #{name}")
      else
        [first | siblings] = String.split(selector, ~r/\s*[~+]\s*/)
        assert first =~ own, "#{selector} reaches outside the package's elements"

        # What a sibling combinator reaches is the package's when it is one of its elements, or
        # when the selector already stands inside one: `.ehg p + span` is, `.ehg ~ p` is not.
        Enum.reduce(siblings, first, fn sibling, before ->
          assert sibling =~ own or before =~ inside,
                 "#{selector} reaches outside the package's elements"

          before <> " + " <> sibling
        end)
      end
    end
  end

  # `text` with every match of `pattern` replaced by `with`, again until none is left, so
  # nested arguments go from the inside out.
  defp strip(text, pattern, with) do
    case Regex.replace(pattern, text, with) do
      ^text -> text
      stripped -> strip(stripped, pattern, with)
    end
  end

  test "NOTICE names each vendored library the bundle carries" do
    notice = File.read!(Path.join(@root, "NOTICE"))

    for file <- File.ls!(Path.join(@root, "assets/vendor")),
        do: assert(notice =~ "assets/vendor/#{file}", "NOTICE does not name #{file}")
  end
end
