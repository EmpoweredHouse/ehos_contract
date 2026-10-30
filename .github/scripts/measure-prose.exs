# Measures the prose of hand-written pages against the sentence rules of `ehos-dev:voice`
# (#517): an instruction has 20 words or fewer, a description 25 or fewer, and a code
# (a refusal or rule code, a layer L1–L5, `§`, a plan name, an issue number) does not
# carry a sentence. Fenced code, HTML comments, tables, headings and images are left out.
#
#     elixir .github/scripts/measure-prose.exs packages/eh_os_contract/docs/contract.md …
#     elixir .github/scripts/measure-prose.exs --long packages/eh_os_contract/docs/contract.md
#
# "Codes" counts every code in running text; "Sentences a code carries" counts the sentences
# with a code outside the parenthesis that closes them. `--long` lists each long sentence and
# each sentence a code carries. The counts are estimates:
# a sentence ends at `.`, `?` or `!` before a space and a capital or a backquote, and an
# instruction is a sentence whose first word is an imperative verb of the list below.

defmodule MeasureProse do
  @imperatives ~w(add ask call change check choose configure declare define do find give keep
                  let link list look make mark name put read record register run see send set
                  show start take tell type use write)

  @code ~r/\b[A-Z][0-9]{1,2}\b|§|\bplan [A-Z]|#[0-9]+/u

  def main(args) do
    {opts, pages} = OptionParser.parse!(args, strict: [long: :boolean])

    rows = Enum.map(pages, &measure/1)

    IO.puts("| Page | Sentences | Long | Codes | Sentences a code carries | Mermaid |")
    IO.puts("| --- | --- | --- | --- | --- | --- |")

    for {page, m} <- rows do
      share = if m.sentences == 0, do: 0, else: round(100 * length(m.long) / m.sentences)

      IO.puts(
        "| `#{page}` | #{m.sentences} | #{length(m.long)} (#{share}%) | #{m.mentions} | " <>
          "#{length(m.codes)} | #{m.mermaid} |"
      )
    end

    if opts[:long] do
      for {page, m} <- rows do
        IO.puts("\n## #{page}")
        for {kind, words, s} <- m.long, do: IO.puts("- long #{kind}, #{words} words: #{s}")
        for s <- m.codes, do: IO.puts("- code: #{s}")
      end
    end
  end

  defp measure(page) do
    text = File.read!(page)
    sentences = text |> prose() |> Enum.flat_map(&sentences/1)

    long =
      for s <- sentences,
          words = words(s),
          kind = if(instruction?(s), do: :instruction, else: :description),
          words > if(kind == :instruction, do: 20, else: 25),
          do: {kind, words, s}

    codes = for s <- sentences, carried?(s), do: s
    mentions = sentences |> Enum.flat_map(&Regex.scan(@code, &1)) |> length()
    mermaid = length(Regex.scan(~r/^```mermaid/mu, text))

    {page,
     %{
       sentences: length(sentences),
       long: long,
       codes: codes,
       mentions: mentions,
       mermaid: mermaid
     }}
  end

  # The page as units of prose: paragraphs and list items, each joined into one line.
  defp prose(text) do
    text
    |> String.replace(~r/^[ ]*```.*?^[ ]*```[ \t]*$/msu, "\n")
    |> String.replace(~r/<!--.*?-->/su, "")
    |> String.split("\n")
    |> Enum.reject(&Regex.match?(~r/^\s*(\||#|!\[|<a id=)/u, &1))
    |> Enum.chunk_while(
      [],
      fn line, acc ->
        cond do
          String.trim(line) == "" -> {:cont, Enum.reverse(acc), []}
          Regex.match?(~r/^\s*([-*+]|[0-9]+\.)\s/u, line) and acc != [] ->
            {:cont, Enum.reverse(acc), [line]}
          true -> {:cont, [line | acc]}
        end
      end,
      fn acc -> {:cont, Enum.reverse(acc), []} end
    )
    |> Enum.map(&(&1 |> Enum.map(fn l -> String.trim(l) end) |> Enum.join(" ")))
    |> Enum.map(&String.replace(&1, ~r/^([-*+]|[0-9]+\.)\s+/u, ""))
    |> Enum.reject(&(&1 == ""))
  end

  defp sentences(unit) do
    unit
    |> String.replace(~r/\[([^\]]*)\]\([^)]*\)/u, "\\1")
    |> String.split(~r/(?<=[.?!])\s+(?=[A-Z`*\[(])/u)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(words(&1) < 3))
  end

  defp words(s), do: s |> String.split(~r/\s+/u, trim: true) |> length()

  defp instruction?(s) do
    first = s |> String.replace(~r/^[*_`]+/u, "") |> String.split(~r/[\s,:]/u) |> hd()
    String.downcase(first) in @imperatives
  end

  # A code carries a sentence unless it stands in the parenthesis that closes it.
  defp carried?(s) do
    s = Regex.replace(~r/\([^()]*\)[.?!]?\s*$/u, s, "")
    Regex.match?(@code, s)
  end
end

MeasureProse.main(System.argv())
