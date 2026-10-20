defmodule EhOsContract.Web.DesignSystemTest do
  @moduledoc """
  The dashboard is styled from the EmpoweredHouse design system, whose tokens and fonts
  `mix assets.build` takes from the `ehos_design` package, and loads nothing from
  another origin (docs/adr/dashboard-design-system.md). The package is a dependency of the
  build only, so these checks read what the build committed, not the package.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhOsContract.Web.TestHost.Access

  @endpoint EhOsContract.Web.TestHost.Endpoint

  @root Path.expand("..", __DIR__)
  @layer Path.join(@root, "assets/css/app.css")
  @built Path.join(@root, "priv/static/assets/app.css")
  @script Path.join(@root, "assets/js/app.js")
  # The graph renderer's stylesheet, which the build imports into the dashboard's (plan E13b).
  @renderer Application.app_dir(:eh_os_contract_graph, "priv/static/eh_os_contract_graph.css")
  @fonts Path.join(@root, "priv/static/assets/fonts")
  @package_tokens Path.join(
                    @root,
                    "deps/ehos_design/packages/ehos_design/priv/css/colors_and_type.css"
                  )

  # The custom properties a stylesheet defines: `--name:` at the start of a declaration.
  defp defined_properties(css) do
    ~r/(?:^|[;{\s])(--[a-z0-9-]+)\s*:/
    |> Regex.scan(css, capture: :all_but_first)
    |> List.flatten()
    |> MapSet.new()
  end

  # The design system's tokens, as the build took them: what the built stylesheet defines that the
  # layer does not.
  defp design_system_properties do
    MapSet.difference(
      @built |> File.read!() |> defined_properties(),
      @layer |> File.read!() |> defined_properties()
    )
  end

  test "the styles take the design system's tokens from the ehos_design package" do
    assert File.read!(@layer) =~
             ~s(@import "../../deps/ehos_design/packages/ehos_design/priv/css/colors_and_type.css";)
  end

  test "the dashboard's styles, as written or as built, name no other origin" do
    for path <- [@layer, @built], css = File.read!(path) do
      refute css =~ ~r/url\(\s*["']?(?:[a-z]+:)?\/\//i, "#{path} loads a url from another origin"

      refute css =~ ~r/@import\s+(?:url\()?\s*["']?(?:[a-z]+:)?\/\//i,
             "#{path} imports from another origin"

      # Not another origin, but not 'self' either: a host's `default-src 'self'` refuses it.
      refute css =~ ~r/url\(\s*["']?data:/i, "#{path} inlines a data: url"
    end
  end

  test "every token the dashboard's styles and scripts read is one the build defines" do
    # A new version of ehos_design that renames a token breaks nothing loudly: CSS falls back to
    # nothing. This is where the rename shows.
    defined = @built |> File.read!() |> defined_properties()

    read =
      for path <- [@layer, @script, @renderer],
          [name] <-
            Regex.scan(~r/(?:var\(|["'])(--[a-z0-9-]+)/, File.read!(path),
              capture: :all_but_first
            ),
          into: MapSet.new(),
          do: name

    assert MapSet.size(read) > 20
    assert MapSet.difference(read, defined) |> Enum.sort() == []
  end

  test "the dashboard's styles refer to the design system's tokens and never redefine one" do
    # The package is not read here, so the check is by name: the layer defines only names under
    # its own prefix, which the design system does not use.
    layer = @layer |> File.read!() |> defined_properties()

    assert MapSet.size(design_system_properties()) > 50
    assert Enum.reject(layer, &String.starts_with?(&1, "--eh-os-contract-")) == []
  end

  test "the built stylesheet carries the design system's tokens, so they reach the page" do
    assert File.read!(@built) =~ "--surface-1:"
  end

  test "every font the styles name is beside the built stylesheet, and served as a font" do
    # Relative to the stylesheet, as written and as built: the built file is what the
    # browser resolves them against.
    written = Regex.scan(~r/url\("(fonts\/[^"]+)"\)/, File.read!(@layer), capture: :all_but_first)

    built =
      Regex.scan(~r/url\("?(fonts\/[^")]+)"?\)/, File.read!(@built), capture: :all_but_first)

    urls = List.flatten(written)
    assert length(urls) == 8
    assert Enum.sort(List.flatten(built)) == Enum.sort(urls)

    for url <- urls do
      response = get(build_conn(), "/eh_os_contract_web/assets/" <> url)
      assert response.status == 200, "#{url} is not served"
      assert ["font/woff2" <> _] = Plug.Conn.get_resp_header(response, "content-type")
    end

    # `mix assets.build` only adds: a font a new ehos_design drops would stay here, served and
    # shipped, and so would anything else that came along with the fonts.
    licences = ["OFL-albert-sans.txt", "OFL-jetbrains-mono.txt"]
    assert Enum.sort(File.ls!(@fonts)) == Enum.sort(licences ++ Enum.map(urls, &Path.basename/1))
  end

  # The package is a `:dev` dependency, so it is here only where someone fetched it — never in
  # CI. Where it is, this catches a `ref:` moved without `mix assets.build`, and a layer that
  # takes one of its names.
  if File.exists?(@package_tokens) do
    test "the build carries every token of the fetched ehos_design, and the layer takes none" do
      package = @package_tokens |> File.read!() |> defined_properties()
      built = @built |> File.read!() |> defined_properties()
      layer = @layer |> File.read!() |> defined_properties()

      assert MapSet.size(package) > 50

      assert MapSet.difference(package, built) |> Enum.sort() == [],
             "the built stylesheet lacks tokens of ehos_design; run `mix assets.build`"

      assert MapSet.intersection(package, layer) |> Enum.sort() == []
    end
  end

  test "the page loads its styles and scripts from the package's own assets" do
    document =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/contract")
      |> html_response(200)
      |> LazyHTML.from_document()

    for link <- LazyHTML.query(document, "link[rel=stylesheet]") do
      [href] = LazyHTML.attribute(link, "href")
      assert String.starts_with?(href, "/eh_os_contract_web/assets/"), "a stylesheet from #{href}"
    end

    for script <- LazyHTML.query(document, "script") do
      sources = LazyHTML.attribute(script, "src")
      assert length(sources) == 1, "an inline script"

      assert String.starts_with?(hd(sources), "/eh_os_contract_web/assets/"),
             "a script from #{hd(sources)}"
    end
  end

  # EHOS serves `default-src 'self'` (plan EG3), which refuses every inline style.
  # What the server sends; what the renderer draws in the browser is its own package's test.
  test "no page carries an inline style as the server sends it" do
    for path <- ["/dashboard/contract", "/dashboard/graph"] do
      document =
        build_conn()
        |> Access.put_actor("admin", ["eh_os_contract_admin"])
        |> get(path)
        |> html_response(200)
        |> LazyHTML.from_document()

      assert Enum.empty?(LazyHTML.query(document, "style")), "#{path}: a <style> element"
      assert Enum.empty?(LazyHTML.query(document, "[style]")), "#{path}: a style attribute"
    end
  end

  test "the nav marks the page being viewed, and only that page" do
    conn = Access.put_actor(build_conn(), "admin", ["eh_os_contract_admin"])

    {:ok, view, _html} = live(conn, "/dashboard/contract")
    assert has_element?(view, ~s(nav a[href="/dashboard/contract"][aria-current=page]))
    refute has_element?(view, ~s(nav a[href="/dashboard/graph"][aria-current]))

    {:ok, view, _html} = live(conn, "/dashboard/graph")
    assert has_element?(view, ~s(nav a[href="/dashboard/graph"][aria-current=page]))
    refute has_element?(view, ~s(nav a[href="/dashboard/contract"][aria-current]))
  end
end
