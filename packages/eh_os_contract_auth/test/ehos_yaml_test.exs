defmodule EhOsContract.Auth.EhosYamlTest do
  @moduledoc """
  EH2: `ehos.yaml` read as strictly as EHOS reads it (`eh-os` D-51), so the manifest
  never carries a value from a file EHOS's checking page refuses.

  The corpus is one file per refusal, in `test/fixtures/ehos_yaml/refused/`. The
  accepted files are the example of `eh-os` `docs/ehos-yaml.md` (at `f7b2330`) and
  the `ehos.yaml` of `EmpoweredHouse/ehos-ledger` (at `341fc19`), unchanged.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Auth.EhosYaml

  @fixtures Path.expand("fixtures/ehos_yaml", __DIR__)
  @only_json "is refused: ehos.yaml holds only what JSON can"

  # Each file of the corpus, with the one reason it is refused for: its path, its line and its
  # message.
  @refused %{
    "alias.yaml" => {"", 6, "an alias (*port) #{@only_json}"},
    "anchor.yaml" => {"", 2, "an anchor (&probe) #{@only_json}"},
    "tag.yaml" => {"", 3, "a tag (tag:yaml.org,2002:int) #{@only_json}"},
    "directive.yaml" => {"", 1, "a directive is refused: ehos.yaml is YAML 1.2 as it is"},
    "two_documents.yaml" => {"", 6, "the file holds more than one YAML document"},
    "duplicate_key.yaml" =>
      {"health.port", 6, "is given twice in one mapping; the first is on line 3"},
    "key_not_a_string.yaml" => {"", 6, "has a key that is not a string"},
    "infinity.yaml" => {"health.port", 3, "is a number JSON cannot hold"},
    "escaped_nul.yaml" => {"health.ready", 4, "holds a NUL character"},
    "not_utf8.yaml" => {"", nil, "the file is not UTF-8 text"},
    "not_yaml.yaml" => {"", 2, "the file is not YAML: Unfinished flow collection"},
    "empty.yaml" => {"", nil, "the file holds no YAML document"},
    "not_a_mapping.yaml" => {"", 1, "must be a mapping"}
  }

  describe "the corpus of refusals" do
    test "every file in it has its reason here, and every reason its file" do
      files =
        @fixtures |> Path.join("refused/*.yaml") |> Path.wildcard() |> Enum.map(&Path.basename/1)

      assert Enum.sort(files) == @refused |> Map.keys() |> Enum.sort()
    end

    for {file, {path, line, message}} <- @refused do
      test "#{file} is refused at #{inspect(path)}, line #{inspect(line)}" do
        text = File.read!(Path.join([@fixtures, "refused", unquote(file)]))

        assert EhosYaml.read(text) ==
                 {:error,
                  [%{path: unquote(path), line: unquote(line), message: unquote(message)}]}
      end
    end
  end

  describe "an accepted file" do
    test "is read into JSON's data model, keys as strings and ports as integers" do
      for file <- ["ehos_yaml_docs.yaml", "ledger.yaml"] do
        text = File.read!(Path.join([@fixtures, "accepted", file]))

        assert EhosYaml.read(text) ==
                 {:ok,
                  %{
                    "schema" => "ehos.yaml/v1",
                    "needs" => %{
                      "database" => %{
                        "engine" => "postgres",
                        "version" => ">= 16",
                        "migrate" => ["/app/bin/migrate"]
                      }
                    },
                    "serves" => [%{"name" => "web", "port" => 4000, "public" => true}],
                    "health" => %{
                      "port" => 4001,
                      "ready" => "/health/ready",
                      "live" => "/health/live"
                    }
                  }},
               file
      end
    end

    test "has its plain values resolved by YAML 1.2's core schema, where yes is a string" do
      assert {:ok, data} = EhosYaml.read("a: yes\nb: on\nc: true\nd: 16\ne: ~\nf: '16'\n")
      assert data == %{"a" => "yes", "b" => "on", "c" => true, "d" => 16, "e" => nil, "f" => "16"}
    end
  end

  test "every reason is reported, sorted by line, those without one first" do
    text = "a: 1\na: 2\nb: .inf\nc: .nan\n"

    assert {:error, errors} = EhosYaml.read(text)
    assert Enum.map(errors, &{&1.path, &1.line}) == [{"a", 2}, {"b", 3}, {"c", 4}]
  end

  test "a key that is not an identifier is quoted in the path, as EHOS quotes it" do
    assert {:error, [%{path: ~s(needs["data base"].x)}]} =
             EhosYaml.read("needs:\n  \"data base\":\n    x: 1\n    x: 2\n")
  end

  test "a reason reads as one line, with its line and its path when it has them" do
    assert EhosYaml.format_error(%{path: "health.port", line: 6, message: "is wrong"}) ==
             "line 6: health.port: is wrong"

    assert EhosYaml.format_error(%{path: "", line: nil, message: "is not UTF-8"}) ==
             "is not UTF-8"
  end
end
