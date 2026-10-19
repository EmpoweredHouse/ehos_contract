defmodule Mix.Tasks.Contract.ReleaseFile do
  @shortdoc "Writes a release's release.json: the packages' versions and the interfaces they meet at"

  @moduledoc """
  Writes `release.json` for a release of this repository (`eh-os` D-91, its `docs/releases.md`):
  the engine's version, which the tag `vX.Y.Z` follows, the commit, each package's own version,
  and the interfaces the packages produce and accept.

      $ mix contract.release_file --commit <40 hex> --output _build/release.json

  CI's release job (`.github/workflows/release.yml`) runs it on a tag, and on a commit of
  `main` when started by hand. It lives in `sandbox/`, the one project that depends on all four
  packages, and is never released, so no host carries the task.

  What the file says comes from the packages themselves: each version from its application's
  specification, the manifest's versions from `EhOsContract.Auth.Manifest.schemas/0`. The two
  interfaces with no version on the wire, `eh_os_contract.api` (the routes `EhOsContract.Plug`
  serves) and `ehos.credential` (what `EhOsContract.Auth.verify/2` reads), are named here, and
  raised here when one breaks. `eh_os_contract.graph`, the `graph.v1` document
  `mix eh_os_contract.graph` writes, names its version in its own `schema`, and EHOS takes a
  domain's with a deployment (`eh-os` D-123); its version here follows that `schema`.

  ## Options

    * `--commit` — the commit the release is made from, in full (required).
    * `--output` — where to write it; `release.json` by default.
  """

  use Mix.Task
  use Boundary, classify_to: EhOsContractHost.Application

  @switches [commit: :string, output: :string]

  @packages [:eh_os_contract, :eh_os_contract_auth, :eh_os_contract_web, :eh_os_contract_graph]

  # Raised by hand, beside a `**Breaking:**` line, when a change breaks one: neither carries its
  # version on the wire (`eh-os` D-91).
  @api "eh_os_contract.api/v1"
  @credential "ehos.credential/v1"

  # The graph document names its own version, `eh_os_contract.graph.v1`
  # (`EhOsContract.Graph.Document`), which the release names in D-91's form.
  @graph "eh_os_contract.graph/v1"

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: @switches)

    if rest != [] or not is_binary(opts[:commit]) do
      Mix.raise("Usage: mix contract.release_file --commit <40 hex> [--output <path>]")
    end

    check_commit!(opts[:commit])
    Mix.Task.run("compile")

    output = Keyword.get(opts, :output, "release.json")
    File.write!(output, [Jason.encode_to_iodata!(release(opts[:commit]), pretty: true), "\n"])
    Mix.shell().info("wrote #{output}")
  end

  @doc false
  @spec release(String.t()) :: map()
  def release(commit) do
    packages = Map.new(@packages, &{Atom.to_string(&1), version!(&1)})

    %{
      "schema" => "ehos.release/v1",
      "component" => "eh_os_contract",
      "version" => packages["eh_os_contract"],
      "commit" => commit,
      "produces" => EhOsContract.Auth.Manifest.schemas() ++ [@api, @graph],
      "accepts" => [@credential],
      "requires" => %{},
      "packages" => packages
    }
  end

  defp version!(app) do
    case Application.load(app) do
      :ok -> :ok
      {:error, {:already_loaded, ^app}} -> :ok
      {:error, reason} -> Mix.raise("cannot load #{app}: #{inspect(reason)}")
    end

    app |> Application.spec(:vsn) |> List.to_string()
  end

  # A release names its commit in full; an empty `$COMMIT` in a script must not pass as one.
  defp check_commit!(commit) do
    unless commit =~ ~r/\A[0-9a-f]{40}\z/ do
      Mix.raise("--commit is a full commit, 40 lowercase hex characters, not #{inspect(commit)}")
    end
  end
end
