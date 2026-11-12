defmodule EhOsContract.Auth.Development.Page do
  @moduledoc false
  # The HTML of `/dev/sign-in`, for `EhOsContract.Auth.Development.Router`: one form, no
  # script, no asset, every value escaped.

  import Plug.HTML, only: [html_escape: 1]

  @style """
  body{font:15px/1.5 system-ui,sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem;color:#1a1a1a}
  h1{font-size:1.4rem}fieldset{border:1px solid #ccc;border-radius:6px;margin:0 0 1rem;padding:.5rem 1rem}
  label{display:block;margin:.4rem 0}small{color:#555;display:block;margin-left:1.6rem}
  input[type=text]{font:inherit;padding:.3rem;width:100%;box-sizing:border-box}
  .error{background:#fde8e8;border:1px solid #e0a0a0;border-radius:6px;padding:.5rem 1rem}
  button{font:inherit;padding:.4rem 1rem}
  """

  @spec render(keyword()) :: iodata()
  def render(assigns) do
    actors = Keyword.fetch!(assigns, :actors)

    [
      "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
      "<title>Development sign-in</title><style>",
      @style,
      "</style></head><body><h1>Development sign-in</h1>",
      "<p>Sign in as a person with actors of the domain. The key that signs the credential ",
      "was made when the application started; EHOS did not issue it.</p>",
      error(assigns[:error]),
      "<form method=\"post\" action=\"/dev/sign-in\">",
      hidden("_csrf_token", Keyword.fetch!(assigns, :csrf_token)),
      hidden("return_to", Keyword.fetch!(assigns, :return_to)),
      "<fieldset><legend>Person</legend><label>Subject ",
      "<input type=\"text\" name=\"subject\" placeholder=\"dev\" value=\"",
      escape(assigns[:subject] || ""),
      "\"></label></fieldset>",
      actors(actors, Keyword.get(assigns, :chosen, [])),
      scopes(actors, Keyword.get(assigns, :scopes, %{})),
      "<button type=\"submit\">Sign in</button></form></body></html>"
    ]
  end

  defp error(nil), do: []
  defp error(message), do: ["<p class=\"error\" role=\"alert\">", escape(message), "</p>"]

  defp actors([], _chosen),
    do: "<p>The contracts grant no actor a capability, so there is nobody to sign in as.</p>"

  defp actors(actors, chosen) do
    [
      "<fieldset><legend>Actors</legend>",
      for actor <- actors do
        [
          "<label><input type=\"checkbox\" name=\"actors[]\" value=\"",
          escape(actor.role),
          "\"",
          if(actor.role in chosen, do: " checked", else: ""),
          "> ",
          escape(actor.role),
          "<small>",
          escape(Enum.join(actor.capabilities, ", ")),
          "</small></label>"
        ]
      end,
      "</fieldset>"
    ]
  end

  defp scopes(actors, values) do
    case actors |> Enum.flat_map(& &1.scopes) |> Enum.uniq() |> Enum.sort() do
      [] ->
        []

      scopes ->
        [
          "<fieldset><legend>Scopes</legend>",
          for scope <- scopes do
            needed_by = for actor <- actors, scope in actor.scopes, do: actor.role

            [
              "<label>",
              escape(scope),
              " <input type=\"text\" name=\"scopes[",
              escape(scope),
              "]\" value=\"",
              escape(Map.get(values, scope, "")),
              "\"><small>for ",
              escape(Enum.join(needed_by, ", ")),
              "</small></label>"
            ]
          end,
          "</fieldset>"
        ]
    end
  end

  defp hidden(name, value),
    do: ["<input type=\"hidden\" name=\"", name, "\" value=\"", escape(value), "\">"]

  defp escape(value), do: html_escape(to_string(value))
end
