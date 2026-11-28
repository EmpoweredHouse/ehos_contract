defmodule Mix.Tasks.Contract.ReleaseFileTest do
  @moduledoc """
  `mix contract.release_file` writes the `release.json` a release of this repository carries:
  the engine's version, the commit, each package's own version, and the
  interfaces the packages produce and accept.
  """

  use ExUnit.Case, async: false

  alias Mix.Tasks.Contract.ReleaseFile

  @commit "0123456789abcdef0123456789abcdef01234567"

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
  end

  @tag :tmp_dir
  test "writes the engine's version, the commit, every package's own version and the interfaces",
       %{tmp_dir: dir} do
    output = Path.join(dir, "release.json")
    ReleaseFile.run(["--commit", @commit, "--output", output])

    assert_received {:mix_shell, :info, ["wrote " <> ^output]}

    vsn = &(&1 |> Application.spec(:vsn) |> List.to_string())

    assert output |> File.read!() |> Jason.decode!() == %{
             "schema" => "ehos.release/v1",
             "component" => "ehos_contract",
             "version" => EhosContract.version(),
             "commit" => @commit,
             "produces" => [
               "ehos.manifest/v2",
               "ehos.manifest/v3",
               "ehos.manifest/v4",
               "ehos.manifest/v5",
               "ehos.manifest/v6",
               "ehos.manifest/v7",
               "ehos.manifest/v8",
               "ehos.manifest/v9",
               "ehos.manifest/v10",
               "ehos_contract.api/v1",
               "ehos_contract.graph/v1"
             ],
             "accepts" => ["ehos.credential/v1"],
             "requires" => %{},
             "packages" => %{
               "ehos_contract" => EhosContract.version(),
               "ehos_contract_auth" => vsn.(:ehos_contract_auth),
               "ehos_contract_web" => vsn.(:ehos_contract_web),
               "ehos_contract_graph" => vsn.(:ehos_contract_graph)
             }
           }
  end

  # What a release produces is what the manifest generator can write, not a list kept here.
  test "produces the manifest versions EhosContract.Auth.Manifest writes" do
    produces = ReleaseFile.release(@commit)["produces"]

    assert produces -- ["ehos_contract.api/v1", "ehos_contract.graph/v1"] ==
             EhosContract.Auth.Manifest.schemas()
  end

  # The graph document names its version in its own `schema`; the release names that version in
  # its own form, `<name>/v<n>`, so a v2 of the document cannot ship with the release still saying
  # v1.
  test "produces the graph document's version, as its JSON Schema names it" do
    [named] =
      EhosContract.Graph.Document.schema_path()
      |> File.read!()
      |> Jason.decode!()
      |> schema_consts()
      |> Enum.uniq()

    [name, "v" <> version] = String.split(named, ~r/\.(?=v\d+\z)/)
    assert "#{name}/v#{version}" in ReleaseFile.release(@commit)["produces"]
  end

  test "refuses a commit that is not 40 lowercase hex characters, and writes nothing" do
    for commit <- [
          "",
          "0123456",
          String.upcase(@commit),
          @commit <> "0",
          "g" <> String.slice(@commit, 1..-1//1)
        ] do
      assert_raise Mix.Error, ~r/--commit is a full commit/, fn ->
        ReleaseFile.run(["--commit", commit, "--output", "/nonexistent/release.json"])
      end
    end
  end

  test "refuses to run without a commit, or with arguments it does not take" do
    for args <- [[], ["--output", "release.json"], ["--commit", @commit, "extra"]] do
      assert_raise Mix.Error, ~r/Usage: mix contract.release_file/, fn ->
        ReleaseFile.run(args)
      end
    end

    assert_raise OptionParser.ParseError, fn -> ReleaseFile.run(["--image", "x"]) end
  end

  defp schema_consts(%{} = map) do
    own =
      case map do
        %{"schema" => %{"const" => named}} when is_binary(named) -> [named]
        _ -> []
      end

    own ++ Enum.flat_map(Map.values(map), &schema_consts/1)
  end

  defp schema_consts(list) when is_list(list), do: Enum.flat_map(list, &schema_consts/1)
  defp schema_consts(_value), do: []
end
