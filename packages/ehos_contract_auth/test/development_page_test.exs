defmodule EhosContract.Auth.DevelopmentPageTest do
  # The look of `/dev/sign-in` (#640): the router's `stylesheet:` option and the page it draws.
  # The page is rendered here directly; `DevelopmentTest` reaches it through the router, where
  # the mode has started.
  use ExUnit.Case, async: true

  alias EhosContract.Auth.Development.{Page, Router}

  @actors [
    %{role: "clinic.manager", capabilities: ["clinic.close_day"], scopes: ["clinic_id"]},
    %{role: "clinic.receptionist", capabilities: ["clinic.book_visit"], scopes: []}
  ]

  defp render(assigns) do
    [actors: @actors, csrf_token: "csrf", return_to: "/"]
    |> Keyword.merge(assigns)
    |> Page.render()
    |> IO.iodata_to_binary()
  end

  test "the router takes the stylesheet's path, Phoenix's by default, or nil" do
    assert Router.init([]) == [stylesheet: "/assets/css/app.css"]
    assert Router.init(stylesheet: "/assets/app.css?v=1") == [stylesheet: "/assets/app.css?v=1"]
    assert Router.init(stylesheet: nil) == [stylesheet: nil]
  end

  test "the router refuses a stylesheet that is not a path of this application, and any other option" do
    for path <- [
          "https://cdn.example/app.css",
          "//cdn.example/app.css",
          "/\\cdn.example/app.css",
          "/\tcdn.example/app.css",
          "assets/css/app.css",
          "",
          :app
        ] do
      assert_raise ArgumentError, ~r/the stylesheet must be a path of this application/, fn ->
        Router.init(stylesheet: path)
      end
    end

    assert_raise ArgumentError, ~r/unknown keys \[:layout\]/, fn -> Router.init(layout: :root) end
  end

  test "the page links the stylesheet after its own rules, escaped, and has no script" do
    page = render(stylesheet: ~s(/assets/app.css?a=1&b="2"))

    assert page =~ ~s(<link rel="stylesheet" href="/assets/app.css?a=1&amp;b=&quot;2&quot;">)

    # The page's layer is declared before the host's stylesheet, so it is the lowest one.
    {style, _} = :binary.match(page, "@layer dev-sign-in{")
    {link, _} = :binary.match(page, "<link rel=\"stylesheet\"")
    assert style < link

    # The token in the page's address never leaves as the stylesheet's referrer.
    {referrer, _} = :binary.match(page, ~s(<meta name="referrer" content="no-referrer">))
    assert referrer < link

    refute page =~ "<script"
    refute render(stylesheet: nil) =~ "<link"
  end

  test "the controls carry daisyUI's classes, and the page's rules read the design system's tokens with a fallback" do
    page = render([])

    assert page =~ ~s(<input class="input" type="text" name="subject")
    assert page =~ ~s(<input class="input" type="text" name="scopes[clinic_id]")
    assert page =~ ~s(<input class="checkbox checkbox-sm" type="checkbox" name="actors[]")
    assert page =~ ~s(<button class="btn btn-primary" type="submit">)

    # Every token the rules read has a fallback, so the page reads without the host's stylesheet.
    tokens = Regex.scan(~r/var\((--[a-z0-9-]+)([,)])/, page)
    assert tokens != []
    assert for([_, token, ")"] <- tokens, do: token) == []
  end
end
