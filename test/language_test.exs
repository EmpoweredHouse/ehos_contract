defmodule PNS.LanguageTest do
  @moduledoc """
  The language rule, enforced instead of written down.

  `CLAUDE.md` has said "the code is in English" for a while and the code was not.
  That is the whole argument for this file: a rule nobody checks quietly stops
  applying, which is the sentence this project applies to contracts and had not
  applied to itself.

  ## What is allowed, and it is narrow

  Polish is legal in exactly one shape: **a single-line double-quoted string**, in
  a file on `@files_with_polish_content`. Everything else is denied everywhere —
  comments, heredocs (so moduledocs and `@doc`), identifiers, atoms.

  The heredoc exclusion is the important one. A moduledoc *is* a string literal,
  so "Polish only in strings" without it would permit exactly the regression this
  test exists to prevent.

  ## Two nets, and the second one is admittedly leaky

  **Non-ASCII** is exact: `ą ć ę ł ń ó ś ź ż` cannot appear outside an allowed
  string. Polish prose of any length essentially always contains one.

  **A stopword list** catches the diacritic-free remainder. It is a heuristic and
  cannot be complete — `rejestry` is Polish and has no diacritics, and it sat in
  the codebase through a full sweep because the first audit's word list did not
  happen to contain it. Words get added here when one slips through; the list
  will never be finished, and pretending otherwise would be the decoration this
  test is against.

  ## Allowlist entries cannot rot

  A file listed here that no longer contains Polish fails the test. Otherwise the
  list grows monotonically and stops meaning anything — the same reason the gate
  table in `docs/contract.md` is bounded by the number of gate tests.
  """

  use ExUnit.Case, async: true

  # Every tree that ships or compiles. `README.md`, `PLAN.md` and `CLAUDE.md` are
  # deliberately absent: repo documentation stays Polish, because it does not
  # travel with the package.
  @roots ~w(lib test config priv/repo/migrations docs)
  @extra_files ~w(mix.exs)

  # This file holds the stopword list and a diacritics regex, so it matches its
  # own rule by construction. Excluding it is honest rather than convenient — but
  # it does mean this is the one file the gate cannot check, which is the standing
  # cost of a checker written in the language it checks.
  @self "test/language_test.exs"

  # Files whose single-line strings may be Polish, with the reason. The reason is
  # not a comment — it is printed when the test fails, so whoever reads the
  # failure learns the rule rather than the list.
  @files_with_polish_content %{
    "lib/taxvision/contracts/accounting_month.ex" =>
      "contract declarations: `label`, `source`, example descriptions and " <>
        "`unavailable_looks_like` are read aloud to the process owner",
    "lib/taxvision/report.ex" => "the evidence report, read by an accountant",
    "lib/taxvision/notifications.ex" => "an email subject and recipients the client's staff see",
    "lib/taxvision/tasks.ex" => "task names the accountant works through",
    "lib/taxvision/registry_check.ex" => "the divergence diff shown to the accountant",
    "test/report_test.exs" => "asserts on the report's own Polish output"
  }

  # Values that come from the client's domain rather than from us: statuses the
  # Polish VAT and company registries actually return. Legal in any file, because
  # allowlisting six test files for one enum value would be noise.
  @domain_values ~w(czynny wykreślony aktywny zwolniony JDG)

  # Deliberately incomplete — see the moduledoc. Only words with no English or
  # Elixir collision; `test` and `handler` were tried and are exactly why this
  # list is a second net rather than the first.
  @stopwords ~w(
    nie jest jako przez bez dla przy oraz tylko wtedy kiedy gdyby jesli czyli
    ktore ktory ktora zeby wiec jednak dlatego poniewaz natomiast znaczy mowi
    byl byla bylo sie tego temu tym nich jego jej nasz nasza nasze swoj swoja
    jedno jeden jedna dwie trzy razy albo lub czy tak nawet juz jeszcze bardzo
    wszystko wszystkie kazdy kazda proces procesu zdarzenie zdarzenia krawedz
    krawedzie wersja wersji okres okresu raport raportu dane danych modul modulu
    plik pliku blad bledy komunikat przebieg przebiegi instancja instancji
    klucza nazwa nazwy opis opisu wartosc liczba liczby lista listy tabela
    tabeli kolumna wiersz krok kroku faza fazy kontrakt kontraktu silnik silnika
    klient klienta firma firmy miesiac ksiegowa rejestr rejestry rejestrow
    wlasnosc zysk zakres dwoch trzech pierwsza druga
  )

  @diacritics ~r/[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]/u

  test "no Polish outside a single-line string in a file allowed to hold client content" do
    violations =
      for path <- sources(),
          {line_no, kind, text} <- polish_outside_strings(path) do
        "#{path}:#{line_no}  (#{kind})  #{String.trim(text)}"
      end

    assert violations == [],
           """
           Polish found where only English belongs.

           The rule: identifiers, comments, moduledocs, `@doc`, test names and any
           text a compiler or a developer reads are English — `lib/pns/` because it
           is a candidate hex package, and everything else because a codebase with
           two languages has two conventions.

           Polish is content, not code. It belongs in a single-line string, in one
           of the files listed in `@files_with_polish_content`.

           #{Enum.join(violations, "\n")}
           """
  end

  test "a file allowed to hold Polish content still holds some" do
    # An allowlist that only ever grows is a list nobody reads. If a file stopped
    # needing its exemption, the entry goes — otherwise the next reader assumes
    # this file is allowed to be Polish anywhere.
    stale =
      for {path, reason} <- @files_with_polish_content,
          File.exists?(path),
          not polish_anywhere?(File.read!(path)) do
        "#{path} — #{reason}"
      end

    assert stale == [],
           """
           These files are allowed to contain Polish and no longer do. Remove the
           entry from `@files_with_polish_content`:

           #{Enum.join(stale, "\n")}
           """
  end

  describe "positive control: the detector still detects" do
    # A gate that has stopped working passes silently, which is worse than no
    # gate. Every case below was tried by hand against the real tree while this
    # file was written, and **two of the three walked straight through the first
    # version** — a Polish variable name, because `_wersja_kontraktu` is one token
    # to a `[A-Za-z_]+` tokenizer and matches no stopword; and a Polish moduledoc,
    # because the phrase happened to carry no diacritics. The first is fixed here.
    # The second is the leak this test admits to and cannot close.

    test "a Polish comment is caught" do
      assert polish_in("# Separator klucza przebiegu")
    end

    test "a Polish identifier is caught, and underscores do not hide it" do
      assert polish_in("_wersja_kontraktu = nil")
      assert polish_in("defp licz_przebiegi(x), do: x")
    end

    test "Polish with diacritics is caught anywhere" do
      assert polish_in("  Jednostki czasu — jedno źródło prawdy.")
    end

    test "ordinary English is not caught" do
      # The other half. A detector that fires on English would be turned off in a
      # week, which is the same failure as one that fires on nothing.
      refute polish_in("# The run key comes from `instance:` and is written on the event")
      refute polish_in("defp first_at_or_after(times, from_at) do")
      refute polish_in("  @doc \"Every handler found in the running binary.\"")
      refute polish_in("assert edge.state == :confirmed")
    end

    test "client domain values are not caught" do
      refute polish_in(~s(@divergent %{vat_status: "wykreślony", vies_status: "aktywny"}))
    end
  end

  test "every allowlisted file exists" do
    # A path that stopped existing takes its exemption with it and nobody notices.
    missing = for {path, _} <- @files_with_polish_content, not File.exists?(path), do: path

    assert missing == [], "allowlisted files that do not exist: #{inspect(missing)}"
  end

  @spec sources() :: [String.t()]
  defp sources do
    from_roots =
      for root <- @roots,
          File.dir?(root),
          path <- Path.wildcard("#{root}/**/*.{ex,exs,md}"),
          do: path

    (from_roots ++ Enum.filter(@extra_files, &File.exists?/1))
    |> Enum.reject(&(&1 == @self))
    |> Enum.sort()
  end

  # Walks a file line by line, tracking heredoc state, and returns everything
  # Polish that is not inside an allowed single-line string.
  @spec polish_outside_strings(String.t()) :: [{pos_integer(), String.t(), String.t()}]
  defp polish_outside_strings(path) do
    allowed_content? = Map.has_key?(@files_with_polish_content, path)
    markdown? = String.ends_with?(path, ".md")

    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({[], false}, fn {line, line_no}, {found, in_heredoc?} ->
      still_heredoc? = toggle_heredoc(in_heredoc?, line)

      # Markdown has no code and no strings: all of it is prose a reader sees, and
      # `docs/` is package documentation, so all of it must be English.
      checked =
        cond do
          markdown? -> line
          in_heredoc? or still_heredoc? != in_heredoc? -> line
          allowed_content? -> strip_single_line_strings(line)
          true -> line
        end

      case polish_in(checked) do
        nil -> {found, still_heredoc?}
        kind -> {[{line_no, kind, line} | found], still_heredoc?}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # A line containing an odd number of `"""` flips heredoc state. A moduledoc's
  # opening and closing lines are themselves treated as heredoc, which is right:
  # `@moduledoc "one-line Polish"` should be caught too.
  @spec toggle_heredoc(boolean(), String.t()) :: boolean()
  defp toggle_heredoc(in_heredoc?, line) do
    if rem(length(String.split(line, ~s(""""))) - 1, 2) == 1, do: not in_heredoc?, else: in_heredoc?
  end

  @spec strip_single_line_strings(String.t()) :: String.t()
  defp strip_single_line_strings(line) do
    line
    |> String.replace(~r/"(?:[^"\\]|\\.)*"/, "")
    |> String.replace(~r/~s\([^)]*\)/, "")
  end

  @spec polish_in(String.t()) :: String.t() | nil
  defp polish_in(text) do
    text = Enum.reduce(@domain_values, text, &String.replace(&2, &1, ""))

    # Split on `_` as well as on non-letters. Without that, `_wersja_kontraktu`
    # is a single token, matches no stopword, and a Polish variable name walks
    # straight through — which it did, until the positive control below caught it.
    words =
      ~r/[A-Za-z]+/
      |> Regex.scan(text)
      |> List.flatten()
      |> Enum.map(&String.downcase/1)
      |> Enum.filter(&(&1 in @stopwords))

    cond do
      Regex.match?(@diacritics, text) -> "non-ASCII"
      words != [] -> "Polish word: #{Enum.join(Enum.uniq(words), ", ")}"
      true -> nil
    end
  end

  # The same detector as the main test, not diacritics alone: `registry_check.ex`
  # holds `rejestry`, which has none, and a diacritics-only staleness check would
  # have called that entry stale and told us to delete a live exemption.
  @spec polish_anywhere?(String.t()) :: boolean()
  defp polish_anywhere?(text) do
    text |> String.split("\n") |> Enum.any?(&(polish_in(&1) != nil))
  end
end
