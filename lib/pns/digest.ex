defmodule PNS.Digest do
  @moduledoc """
  The canonical form of a declaration, and the hash taken over it.

  Both identities of a deployment are hashes — the contract version is a hash of
  the contract's declarations, the wiring version a hash of the handlers' published
  edges (`PNS.Deployment`). They are compared against values written into the log
  weeks earlier, which makes one property non-negotiable: **the same agreement must
  hash the same way every time, on every machine, forever.**

  `:erlang.term_to_binary/1` does not offer that, and using it was a real gap rather
  than a theoretical one. It serialises a runtime representation, so the bytes may
  differ for equal terms across OTP releases — and a changed hash reclassifies the
  entire log as belonging to an older agreement. The evidence report would then say
  the contract changed on a day when nothing changed but the runtime.

  ## What is deliberately insignificant

  **Declaration order in the file.** A contract is a set of declarations, not a
  sequence, so moving an `event` block above another one must not move the version.
  This was the more likely of the two defects: reordering a file is an ordinary
  edit, whereas an OTP upgrade is an event somebody notices.

  **Key order inside a map.** Not observable through map literals, since equal maps
  are equal — but it is observable through the encoding, which is what made the old
  hash depend on something the agreement has no opinion about.

  ## What is deliberately significant

  **The order of a list value stays.** `instance: [:company_id, :period]` and
  `[:period, :company_id]` are different agreements: the run key is those values
  joined in order, so sorting them would make two different keys hash alike.
  `stages:` is the same case — stage order is what makes a backward edge backward
  (`PNS.Check`). So collections *of declarations* are sorted and values *inside* a
  declaration are not, which is the whole distinction this module exists to hold.
  """

  @doc """
  A deterministic string for any declaration term.

  Types are prefixed so that values of different kinds cannot collide: `:x` and
  `"x"` are different declarations and must produce different strings. Maps are
  emitted with their keys sorted by canonical form; lists and tuples keep their
  order, for the reason in the moduledoc.
  """
  @spec canonical(term()) :: String.t()
  def canonical(term)

  def canonical(map) when is_map(map) do
    # `:maps.to_list/1` rather than `Enum`, so a struct — which is also a map, and
    # would otherwise need the Enumerable protocol — canonicalises rather than
    # raising a protocol error during someone's contract compilation.
    inner =
      map
      |> :maps.to_list()
      |> Enum.sort_by(fn {key, _} -> canonical(key) end)
      |> Enum.map_join(",", fn {key, value} -> canonical(key) <> "=" <> canonical(value) end)

    "{" <> inner <> "}"
  end

  def canonical(list) when is_list(list) do
    "[" <> Enum.map_join(list, ",", &canonical/1) <> "]"
  end

  def canonical(tuple) when is_tuple(tuple) do
    "(" <> (tuple |> Tuple.to_list() |> Enum.map_join(",", &canonical/1)) <> ")"
  end

  def canonical(atom) when is_atom(atom), do: "a:" <> Atom.to_string(atom)
  def canonical(binary) when is_binary(binary), do: "s:" <> binary
  def canonical(number) when is_number(number), do: "n:" <> to_string(number)

  @doc """
  A short hash of the canonical form of a term.

  Twelve hex characters: long enough that a collision between two contracts of one
  client is not a practical concern, short enough to be read aloud from a report.
  """
  @spec hash(term()) :: String.t()
  def hash(term) do
    term
    |> canonical()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  @doc """
  A hash of named groups of declarations, with each group's members sorted.

  Sorting happens on the canonical form of a whole declaration rather than on a
  name key, so this needs no knowledge of which key names a declaration — and there
  is no group whose shape it has to be taught. Each group is labelled by its kind,
  so an `event` moving to an empty `external` list cannot produce the same string.
  """
  @spec hash_groups(keyword([map()])) :: String.t()
  def hash_groups(groups) do
    groups
    |> Enum.map_join("\n", fn {kind, declarations} ->
      members = declarations |> Enum.map(&canonical/1) |> Enum.sort() |> Enum.join("\n")
      "#{kind}\n#{members}"
    end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end
end
