defmodule Mix.Tasks.EhOsContract.Dev.Credential do
  @shortdoc "Prints a credential from the application running in the development mode"

  @moduledoc """
  Asks the application running on this computer in the development mode
  (`EhOsContract.Auth.Development`) for a credential, and prints it, for `curl`:

      mix eh_os_contract.dev.credential --actor clinic.receptionist --scope clinic_id=clinic-1

      curl -H "authorization: Bearer $(mix eh_os_contract.dev.credential ...)" \\
        http://localhost:4000/api/commands/clinic.record_payment

  The application signs it with the key it holds in memory, at `/dev/credential` of
  `EhOsContract.Auth.Development.Router`. The key never leaves the application.

  Options:

    * the token the application printed when it started. Without `--token` and
      `EH_OS_CONTRACT_DEV_TOKEN`, it is read from the file the running application writes it
      to, `eh_os_contract_dev_sign_in` in the build directory, such as `_build/dev`. Run the
      command in the application's project, in the same Mix environment. `--token` takes it,
      but a command line is seen by other users of the computer and kept in the shell's
      history;
    * `--actor`: a role of the domain, `<domain>.<actor>`; once per actor, at least once;
    * `--scope`: `<scope>=<value>`, once per scope of the actors' capabilities;
    * `--subject`: the person, `dev` by default;
    * `--url`: the application's address, `http://localhost:4000` by default. Only
      `http://` on `localhost`, `127.0.0.1` or `[::1]`, so the token is not sent anywhere
      else.

  It refuses with the application's reason, and when no application answers there.
  """

  use Boundary, classify_to: EhOsContract.Auth
  use Mix.Task

  @switches [token: :string, actor: :keep, scope: :keep, subject: :string, url: :string]
  @hosts ["localhost", "127.0.0.1", "[::1]"]

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      invalid != [] -> Mix.raise("unknown options: #{Enum.map_join(invalid, " ", &elem(&1, 0))}")
      rest != [] -> Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")
      true -> :ok
    end

    token = opts[:token] || System.get_env("EH_OS_CONTRACT_DEV_TOKEN") || token_from_file!()

    actors = Keyword.get_values(opts, :actor)
    if actors == [], do: Mix.raise("name at least one actor: --actor <domain>.<actor>")

    url = url!(opts[:url] || "http://localhost:4000")
    {:ok, _started} = Application.ensure_all_started(:req)

    body = %{
      subject: opts[:subject] || "dev",
      actors: actors,
      scopes: opts |> Keyword.get_values(:scope) |> Enum.map(&scope!/1) |> Map.new()
    }

    case Req.post(url <> "/dev/credential",
           json: body,
           headers: [{"x-dev-sign-in-token", token}],
           retry: false,
           redirect: false
         ) do
      {:ok, %Req.Response{status: 200, body: %{"credential" => credential}}} ->
        Mix.shell().info(credential)

      {:ok, %Req.Response{status: status, body: body}} ->
        Mix.raise("the application refused, with #{status}: #{reason(body)}")

      {:error, exception} ->
        Mix.raise(
          "no application answered at #{url} (#{Exception.message(exception)}): is it " <>
            "running with mix phx.server, in the development mode?"
        )
    end
  end

  # The token in the address the running application keeps in its file.
  defp token_from_file! do
    file = EhOsContract.Auth.Development.address_file()

    with {:ok, address} <- File.read(file),
         %URI{query: query} when is_binary(query) <- URI.parse(String.trim(address)),
         {:ok, token} when token != "" <- Map.fetch(URI.decode_query(query), "token") do
      token
    else
      _missing ->
        Mix.raise(
          "no token: #{Path.relative_to_cwd(file)} does not hold one, so no application of " <>
            "this project runs in the development mode in this Mix environment. Start it with " <>
            "mix phx.server, or give the token it printed: export EH_OS_CONTRACT_DEV_TOKEN=<token>"
        )
    end
  end

  defp url!(url) do
    case URI.parse(url) do
      %URI{scheme: "http", host: host, userinfo: nil, query: nil, fragment: nil, path: path}
      when path in [nil, "", "/"] ->
        if host in @hosts or "[#{host}]" in @hosts,
          do: String.trim_trailing(url, "/"),
          else: refused_url!(url)

      _other ->
        refused_url!(url)
    end
  end

  defp refused_url!(url) do
    Mix.raise(
      "--url takes http://localhost:<port>, http://127.0.0.1:<port> or http://[::1]:<port>, " <>
        "not #{url}: the token goes only to this computer"
    )
  end

  defp scope!(pair) do
    case String.split(pair, "=", parts: 2) do
      [scope, value] when scope != "" and value != "" -> {scope, value}
      _other -> Mix.raise("--scope takes <scope>=<value>, not #{pair}")
    end
  end

  defp reason(%{"error" => error}), do: error
  defp reason(body) when is_binary(body), do: body
  defp reason(body), do: inspect(body)
end
