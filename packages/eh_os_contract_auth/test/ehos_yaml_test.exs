defmodule EhOsContract.Auth.EhosYamlTest do
  @moduledoc """
  EH2: `ehos.yaml` read as strictly as EHOS reads it, so the manifest
  never carries a value from a file EHOS's checking page refuses.

  The corpus is one file per refusal, in `test/fixtures/ehos_yaml/refused/`. The
  accepted files are the example of EHOS's documentation of `ehos.yaml` and the
  `ehos.yaml` of a real application, a ledger, both as they stood on 1 October 2026
  (the ledger's with its comment's link removed), and a made-up `ehos.yaml/v2` with
  `sign_in`, a made-up `ehos.yaml/v3` that reads the company's people, and a made-up
  `ehos.yaml/v4` that seeds its database and is given secrets.
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
       ~s(must be a version of ehos.yaml this generator knows: ehos.yaml/v1, ehos.yaml/v2, ehos.yaml/v3, ehos.yaml/v4; "ehos.yaml/v9" is not one)},
    "no_health.yaml" => {"health", nil, "is required"},
    "database_without_engine.yaml" => {"needs.database.engine", 3, "is required"},
    "unknown_key.yaml" => {"replicas", 6, "is not a field of ehos.yaml/v1"},
    "unknown_nested_key.yaml" => {"needs.database.size", 5, "is not a field of ehos.yaml/v1"},
    "port_80.yaml" => {"serves[0].port", 4, "must be at least 1024"},
    "version_as_number.yaml" => {"needs.database.version", 5, "must be a string"},
    "public_yes.yaml" => {"serves[0].public", 5, "must be true or false"},
    "application_ehos.yaml" => {"application", 2, "must not be ehos"},
    # What v2 adds, by its schema and the two rules EHOS checks beside it.
    "sign_in_in_v1.yaml" => {"sign_in", 6, "is not a field of ehos.yaml/v1"},
    "sign_in_named_twice.yaml" => {"sign_in.applications", 7, "must list each value once"},
    "sign_in_without_public_web.yaml" =>
      {"sign_in", 5,
       "needs an entry of serves named web with public: true, where sign-in returns"},
    "sign_in_web_not_public.yaml" =>
      {"sign_in", 9,
       "needs an entry of serves named web with public: true, where sign-in returns"},
    "sign_in_own_application.yaml" =>
      {"sign_in.applications[1]", 10, "is the application this file names"}
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

    test "in ehos.yaml/v2 has its sign_in read as it is written" do
      text = File.read!(Path.join([@fixtures, "accepted", "sign_in.yaml"]))

      assert {:ok, %{"schema" => "ehos.yaml/v2", "sign_in" => sign_in}} = EhosYaml.read(text)
      assert sign_in == %{"applications" => ["pages", "billing"]}

      # `{}` asks for the file's own application only, so it is kept as it is, not dropped.
      own = String.replace(text, "sign_in:\n  applications: [pages, billing]\n", "sign_in: {}\n")
      assert own != text
      assert {:ok, %{"sign_in" => own_sign_in}} = EhosYaml.read(own)
      assert own_sign_in == %{}
    end

    test "has its plain values resolved by YAML 1.2's core schema, where yes is a string" do
      text = "a: yes\nb: on\nc: true\nd: 16\ne: ~\nf: '16'\n"

      assert {:ok, data, _lines} = EhOsContract.Auth.EhosYaml.Reader.decode(text)
      assert data == %{"a" => "yes", "b" => "on", "c" => true, "d" => 16, "e" => nil, "f" => "16"}
    end
  end

  describe "ehos.yaml/v3" do
    test "reads needs.people, as written" do
      text = File.read!(Path.join([@fixtures, "accepted", "people.yaml"]))

      assert {:ok, %{"schema" => "ehos.yaml/v3", "needs" => %{"people" => "read"}} = file} =
               EhosYaml.read(text)

      assert file["sign_in"] == %{}
    end

    test "takes read alone, and needs.people only from v3 on" do
      v3 = "schema: ehos.yaml/v3\nneeds:\n  people: write\n" <> @health
      assert {:error, [%{path: "needs.people"}]} = EhosYaml.read(v3)

      v2 = "schema: ehos.yaml/v2\nneeds:\n  people: read\n" <> @health
      assert {:error, [%{path: path}]} = EhosYaml.read(v2)
      assert path in ["needs", "needs.people"]
    end
  end

  describe "ehos.yaml/v4" do
    test "reads needs.database.seed and needs.secrets, as written" do
      text = File.read!(Path.join([@fixtures, "accepted", "secrets.yaml"]))

      assert {:ok, %{"schema" => "ehos.yaml/v4", "needs" => needs}} = EhosYaml.read(text)
      assert needs["database"]["seed"] == ["/app/bin/seed"]

      assert needs["secrets"] == [
               %{"name" => "smtp_password"},
               %{"name" => "gus_api_key", "version" => 2}
             ]
    end

    test "takes a seed and secrets only from v4 on" do
      for version <- ["ehos.yaml/v3", "ehos.yaml/v2"] do
        seed =
          "schema: #{version}\nneeds:\n  database:\n    engine: postgres\n    seed: [x]\n" <>
            @health

        assert {:error, [%{path: path}]} = EhosYaml.read(seed)
        assert path in ["needs.database", "needs.database.seed"]

        secrets = "schema: #{version}\nneeds:\n  secrets:\n    - name: smtp_password\n" <> @health
        assert {:error, [%{path: path}]} = EhosYaml.read(secrets)
        assert path in ["needs", "needs.secrets"]
      end
    end

    test "refuses a secret named as one EHOS gives every workload" do
      text = "schema: ehos.yaml/v4\nneeds:\n  secrets:\n    - name: database_url\n" <> @health
      assert {:error, [%{path: "needs.secrets[0].name", message: message}]} = EhosYaml.read(text)

      assert message ==
               "is a name EHOS reserves: it must not match " <>
                 "^(ehos_|database_|phx_|otel_|pg|release_|erl_|elixir_|ld_|lc_|kubernetes_), " <>
                 "or be secret_key_base, path, home, hostname, lang, shell, user, tmpdir"
    end
  end

  describe "the schema" do
    test "is EHOS's ehos.yaml/v1, byte for byte" do
      # EHOS's `priv/schemas/ehos.yaml/v1.json`, as read on 1 October 2026; the same bytes an
      # application's `.ehos/ehos.yaml.v1.json` holds. A new hash here is a new copy
      # of EHOS's file, never an edit of this one.
      document = File.read!(EhOsContract.Auth.EhosYaml.Schema.file("ehos.yaml/v1"))

      assert :crypto.hash(:sha256, document) |> Base.encode16(case: :lower) ==
               "5dd7ad3491607ea9c8566740c7b7e182923b098dfee219c0be3f2372e36b515b"

      assert Jason.decode!(document)["title"] == "ehos.yaml/v1"
    end

    test "is EHOS's ehos.yaml/v2, byte for byte" do
      # EHOS's `priv/schemas/ehos.yaml/v2.json`, the version that adds sign-in, as read on
      # 2 October 2026, in no release yet. A new hash here is a new copy of EHOS's file.
      document = File.read!(EhOsContract.Auth.EhosYaml.Schema.file("ehos.yaml/v2"))

      assert :crypto.hash(:sha256, document) |> Base.encode16(case: :lower) ==
               "de533072d4c617aee4dfdaee71cf736feed2939a7446e8a52ee8d96879788c38"

      assert Jason.decode!(document)["title"] == "ehos.yaml/v2"
    end

    test "is EHOS's ehos.yaml/v3, byte for byte" do
      # EHOS's `priv/schemas/ehos.yaml/v3.json`, the version that reads the company's people, as
      # read on 8 October 2026. A new hash here is a new copy of EHOS's file.
      document = File.read!(EhOsContract.Auth.EhosYaml.Schema.file("ehos.yaml/v3"))

      assert :crypto.hash(:sha256, document) |> Base.encode16(case: :lower) ==
               "1d4b59df52142db7247112f88d27c6c92021186d0a51c525dc94d1a71be8b8e4"

      assert Jason.decode!(document)["title"] == "ehos.yaml/v3"
    end

    test "is EHOS's ehos.yaml/v4, byte for byte" do
      # EHOS's `priv/schemas/ehos.yaml/v4.json`, the version that adds a seed and secrets, as
      # read on 17 October 2026. A new hash here is a new copy of EHOS's file.
      document = File.read!(EhOsContract.Auth.EhosYaml.Schema.file("ehos.yaml/v4"))

      assert :crypto.hash(:sha256, document) |> Base.encode16(case: :lower) ==
               "74469f3cfb8679fc3a3f445c58bef21564c1748f0896000bf1a986c147ed9563"

      assert Jason.decode!(document)["title"] == "ehos.yaml/v4"
    end

    test "are v1 to v4" do
      assert EhosYaml.versions() == [
               "ehos.yaml/v1",
               "ehos.yaml/v2",
               "ehos.yaml/v3",
               "ehos.yaml/v4"
             ]
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

  describe "EHOS's bounds, kept without its budgets" do
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

    test "nesting deeper than 16 levels is refused as the parser reaches it, as EHOS refuses it" do
      # Block sequences need no bracket, and the reader's work grew with the square of the depth:
      # 8000 levels, 16 KB, took seconds before the file was refused.
      assert EhosYaml.read(String.duplicate("- ", 16) <> "x\n") ==
               {:error, [%{path: "", line: 1, message: "must be a mapping"}]}

      for depth <- [17, 8000] do
        assert EhosYaml.read(String.duplicate("- ", depth) <> "x\n") ==
                 {:error, [%{path: "", line: 1, message: "nests deeper than 16 levels"}]}
      end
    end

    test "depth is how deep a file nests, not how many collections it holds" do
      # 40 serves, each a mapping in a list, beside the rest: 44 collections, four levels deep.
      serves = Enum.map_join(1..40, "", &"  - name: web#{&1}\n    port: #{4100 + &1}\n")
      text = "schema: ehos.yaml/v1\nserves:\n" <> serves <> @health

      assert {:error, [%{path: "serves", message: "must list at most 16"}]} = EhosYaml.read(text)
    end

    test "a list of more than 256 entries is refused whole, not entry by entry" do
      text = "schema: ehos.yaml/v1\nserves:\n" <> String.duplicate("  - 1\n", 257) <> @health

      assert EhosYaml.read(text) ==
               {:error, [%{path: "serves", line: 2, message: "lists more than 256 entries"}]}
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

  test "an escape past Unicode's last code point is refused, in a value or a key" do
    assert EhosYaml.read(~S(schema: "\U00110000") <> "\n") ==
             {:error,
              [%{path: "schema", line: 1, message: "holds a character that is not Unicode"}]}

    assert EhosYaml.read(~S("\U00110000": 1) <> "\n") ==
             {:error,
              [
                %{
                  path: "",
                  line: 1,
                  message: "has a key that holds a character that is not Unicode"
                }
              ]}
  end

  test "a file that is not a mapping is refused at the line it begins on, not at a comment" do
    assert EhosYaml.read("# ehos.yaml\n# for the ledger\n- schema: ehos.yaml/v1\n") ==
             {:error, [%{path: "", line: 3, message: "must be a mapping"}]}
  end

  test "text yamerl raises on is refused with what it raised" do
    assert EhosYaml.read(":") ==
             {:error,
              [
                %{
                  path: "",
                  line: nil,
                  message:
                    "the file is not YAML that can be read: no function clause matching in " <>
                      ":yamerl_parser.parse_mapping_value/5"
                }
              ]}
  end

  # Both of `sign_in`'s rules, once the schema has passed: neither stops the other.
  test "sign_in breaking both its rules is refused for each" do
    text =
      "schema: ehos.yaml/v2\napplication: ledger\nsign_in:\n  applications: [ledger]\n" <> @health

    assert EhosYaml.read(text) ==
             {:error,
              [
                %{
                  path: "sign_in",
                  line: 3,
                  message:
                    "needs an entry of serves named web with public: true, where sign-in returns"
                },
                %{
                  path: "sign_in.applications[0]",
                  line: 4,
                  message: "is the application this file names"
                }
              ]}
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

defmodule EhOsContract.Auth.EhosYamlNodeModsTest do
  @moduledoc """
  yamerl's application environment: a host's `config :yamerl, node_mods:` adds to the
  core schema in every read in the VM, so a value is read as EHOS would not read it,
  and such a node is refused; and yamerl reads its options from there, so it must be
  loaded, though nothing starts it. Not async: it changes yamerl's environment.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.Auth.EhosYaml

  setup do
    Application.load(:yamerl)
    previous = Application.fetch_env(:yamerl, :node_mods)
    Application.put_env(:yamerl, :node_mods, [:yamerl_node_bool_ext])

    on_exit(fn ->
      case previous do
        {:ok, mods} -> Application.put_env(:yamerl, :node_mods, mods)
        :error -> Application.delete_env(:yamerl, :node_mods)
      end
    end)
  end

  test "a file reads though yamerl was never loaded, as in a Mix task, where it is not started" do
    assert :ok = Application.unload(:yamerl)

    assert {:ok, %{"health" => %{"port" => 4001}}} =
             EhosYaml.read(
               "schema: ehos.yaml/v1\nhealth:\n  port: 4001\n  ready: /health/ready\n  live: /health/live\n"
             )
  end

  test "a value another node module reads is refused, not read as true" do
    text =
      "schema: ehos.yaml/v1\nserves:\n  - name: web\n    port: 4000\n    public: yes\n" <>
        "health:\n  port: 4001\n  ready: /health/ready\n  live: /health/live\n"

    assert EhosYaml.read(text) ==
             {:error,
              [
                %{
                  path: "serves[0].public",
                  line: 5,
                  message:
                    "is read by :yamerl_node_bool_ext, not by YAML 1.2's core schema: remove it " <>
                      "from config :yamerl, node_mods"
                }
              ]}
  end
end
