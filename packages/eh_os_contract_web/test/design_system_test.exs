defmodule EhOsContract.Web.DesignSystemTest do
  @moduledoc """
  The dashboard is styled from a copy of the EmpoweredHouse design system, refreshed from
  Claude Design and never edited by hand, and loads nothing from another origin
  (docs/adr/dashboard-design-system.md, following eh-os D-42). The same checks as the
  EHOS console's, with this package's paths.
  """

  use EhOsContract.Web.TestHost.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias EhOsContract.Web.TestHost.Access

  @endpoint EhOsContract.Web.TestHost.Endpoint

  @root Path.expand("..", __DIR__)
  @copy Path.join(@root, "assets/css/vendor/empoweredhouse/colors_and_type.css")
  @source Path.join(@root, "assets/css/vendor/empoweredhouse/SOURCE.md")
  @layer Path.join(@root, "assets/css/app.css")
  @built Path.join(@root, "priv/static/assets/app.css")
  @fonts Path.join(@root, "priv/static/assets/fonts")

  # The custom properties a stylesheet defines: `--name:` at the start of a declaration.
  defp defined_properties(css) do
    ~r/(?:^|[;{\s])(--[a-z0-9-]+)\s*:/
    |> Regex.scan(css, capture: :all_but_first)
    |> List.flatten()
    |> MapSet.new()
  end

  test "the copy is the file SOURCE.md records, so it has not been edited by hand" do
    [recorded] =
      Regex.run(~r/SHA-256 as committed \| `([0-9a-f]{64})`/, File.read!(@source),
        capture: :all_but_first
      )

    actual = :crypto.hash(:sha256, File.read!(@copy)) |> Base.encode16(case: :lower)

    assert actual == recorded,
           "assets/css/vendor/empoweredhouse/colors_and_type.css differs from what SOURCE.md " <>
             "records. Refresh it from Claude Design and update SOURCE.md, rather than editing it."
  end

  test "git keeps the copy's bytes as they are, so its hash holds on every checkout" do
    attributes = @root |> Path.join(".gitattributes") |> File.read!() |> String.split("\n")

    assert "assets/css/vendor/empoweredhouse/colors_and_type.css -text" in attributes
  end

  test "neither the copy nor the dashboard's styles, as written or as built, name another origin" do
    for path <- [@copy, @layer, @built], css = File.read!(path) do
      refute css =~ ~r/url\(\s*["']?(?:[a-z]+:)?\/\//i, "#{path} loads a url from another origin"

      refute css =~ ~r/@import\s+(?:url\()?\s*["']?(?:[a-z]+:)?\/\//i,
             "#{path} imports from another origin"
    end
  end

  test "the dashboard's styles refer to the design system's tokens and never redefine one" do
    copy = @copy |> File.read!() |> defined_properties()
    layer = @layer |> File.read!() |> defined_properties()

    assert MapSet.size(copy) > 50
    assert MapSet.intersection(copy, layer) |> Enum.sort() == []
  end

  test "the built stylesheet carries the copy, so the tokens reach the page" do
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

    assert File.exists?(Path.join(@fonts, "OFL-albert-sans.txt"))
    assert File.exists?(Path.join(@fonts, "OFL-jetbrains-mono.txt"))
  end

  test "the page loads its styles and scripts from the package's own assets" do
    document =
      build_conn()
      |> Access.put_actor("admin", ["eh_os_contract_admin"])
      |> get("/dashboard/contract")
      |> html_response(200)
      |> LazyHTML.from_document()

    for link <- LazyHTML.query(document, "link[rel=stylesheet]") do
      assert [href] = LazyHTML.attribute(link, "href")
      assert String.starts_with?(href, "/eh_os_contract_web/assets/"), "a stylesheet from #{href}"
    end

    for script <- LazyHTML.query(document, "script") do
      assert [src] = LazyHTML.attribute(script, "src"), "an inline script"
      assert String.starts_with?(src, "/eh_os_contract_web/assets/"), "a script from #{src}"
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
