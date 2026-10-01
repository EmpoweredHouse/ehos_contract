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
  @health "health:\n  port: 4001\n  ready: /health/ready\n  live: /health/live\n"

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
    "not_a_mapping.yaml" => {"", 1, "must be a mapping"},
    # What the schema refuses, at the line of the value's key, or of the mapping a missing key
    # belongs in.
    "no_schema.yaml" =>
      {"schema", nil, "is required: it names the version of ehos.yaml the file is in"},
    "unknown_version.yaml" =>
      {"schema", 1,
       ~s(must be a version of ehos.yaml this generator knows: ehos.yaml/v1; "ehos.yaml/v9" is not one)},
    "no_health.yaml" => {"health", nil, "is required"},
    "database_without_engine.yaml" => {"needs.database.engine", 3, "is required"},
    "unknown_key.yaml" => {"replicas", 6, "is not a field of ehos.yaml/v1"},
    "unknown_nested_key.yaml" => {"needs.database.size", 5, "is not a field of ehos.yaml/v1"},
    "port_80.yaml" => {"serves[0].port", 4, "must be at least 1024"},
    "version_as_number.yaml" => {"needs.database.version", 5, "must be a string"},
    "public_yes.yaml" => {"serves[0].public", 5, "must be true or false"},
    "application_ehos.yaml" => {"application", 2, "must not be ehos"}
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
      text = "a: yes\nb: on\nc: true\nd: 16\ne: ~\nf: '16'\n"

      assert {:ok, data, _lines} = EhOsContract.Auth.EhosYaml.Reader.decode(text)
      assert data == %{"a" => "yes", "b" => "on", "c" => true, "d" => 16, "e" => nil, "f" => "16"}
    end
  end

  describe "the schema" do
    test "is EHOS's ehos.yaml/v1, byte for byte" do
      # `eh-os` `priv/schemas/ehos.yaml/v1.json`, last changed in `eeb732a`, read at `f7b2330`;
      # the same bytes as `ehos-ledger`'s `.ehos/ehos.yaml.v1.json`. A new hash here is a new copy
      # of EHOS's file, never an edit of this one.
      document = File.read!(EhOsContract.Auth.EhosYaml.Schema.file("ehos.yaml/v1"))

      assert :crypto.hash(:sha256, document) |> Base.encode16(case: :lower) ==
               "5dd7ad3491607ea9c8566740c7b7e182923b098dfee219c0be3f2372e36b515b"

      assert Jason.decode!(document)["title"] == "ehos.yaml/v1"
    end

    test "is the only version read" do
      assert EhosYaml.versions() == ["ehos.yaml/v1"]
    end

    test "fills in no default: public is absent when the file does not write it" do
      text = "schema: ehos.yaml/v1\nserves:\n  - name: web\n    port: 4000\n" <> @health

      assert {:ok, %{"serves" => [serve]}} = EhosYaml.read(text)
      assert serve == %{"name" => "web", "port" => 4000}
    end

    test "reports every value it refuses, not the first" do
      text =
        "schema: ehos.yaml/v1\nhealth:\n  port: 80\n  ready: here\n  live: /live\n  mode: x\n"

      assert {:error, errors} = EhosYaml.read(text)

      assert Enum.map(errors, &{&1.path, &1.line}) == [
               {"health.port", 3},
               {"health.ready", 4},
               {"health.mode", 6}
             ]
    end
  end

  describe "EHOS's bounds that a valid file can break" do
    test "a file of more than 64 KiB is refused, though comments are all that make it large" do
      text = "schema: ehos.yaml/v1\n" <> @health <> String.duplicate("# padding\n", 6554)

      assert byte_size(text) > 65_536

      assert EhosYaml.read(text) ==
               {:error,
                [
                  %{
                    path: "",
                    line: nil,
                    message: "the file is #{byte_size(text)} bytes; EHOS reads at most 65536"
                  }
                ]}
    end

    test "more than 256 of [ and { are refused, inside a quoted string too" do
      migrate = fn braces ->
        "schema: ehos.yaml/v1\nneeds:\n  database:\n    engine: postgres\n" <>
          "    migrate: [\"/app/bin/migrate\", \"#{String.duplicate("{", braces)}\"]\n" <> @health
      end

      # The list itself is one `[`.
      assert {:ok, _data} = EhosYaml.read(migrate.(255))

      assert EhosYaml.read(migrate.(256)) ==
               {:error,
                [
                  %{
                    path: "",
                    line: nil,
                    message: "the file holds more than 256 of [ and {, which EHOS does not read"
                  }
                ]}
    end
  end

  test "every reason the reader finds is reported, sorted by line, those without one first" do
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
