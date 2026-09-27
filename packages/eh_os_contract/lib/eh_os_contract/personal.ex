defmodule EhOsContract.Personal do
  @moduledoc """
  Personal data in the log (v2 §14): each subject's data key, and the personal
  fields of events sealed with it.

  **A key per subject.** A subject — a person whose data may be erased, `subject
  :patient` in the domain — gets a data key, 32 random bytes, the first time an
  event carries its personal data. The key is stored in
  `eh_os_contract_subject_keys` only wrapped by `EhOsContract.Vault`. It is made
  and wrapped before the append lock and stored under it (`prepare/2`,
  `for_writing/2`), so two dispatches never create two and no writer waits on the
  vault. Deleting a
  subject's keys is what erases it: every personal field sealed with them reads
  back as `EhOsContract.Erased`.

  **A sealed field.** Its value in the log's form is JSON-encoded and encrypted with
  AES-256-GCM under the subject's key: a 12-byte random IV, and as additional data
  `type|field|subject|key_version`, so a ciphertext cannot be moved to another
  event type, field or subject. It is stored as
  `{"$eh": "enc1", "k": key_version, "d": base64(iv <> tag <> ciphertext)}`. The
  subject's id stays in the clear in its own field: the log says whose data it was.

  **No cache.** Keys are read for one batch of events and dropped with it: a cache
  on another node would outlive an erasure.
  """

  import Ecto.Query

  alias EhOsContract.{Codec, Vault}

  @keys "eh_os_contract_subject_keys"
  @erasures "eh_os_contract_erasures"

  @typedoc "A subject: its type, as the domain declares it, and its id."
  @type subject :: {atom(), String.t()}

  @typedoc "Data keys for reading, by subject type, subject id and key version."
  @type keys :: %{{String.t(), String.t(), pos_integer()} => binary()}

  @typedoc "Data keys for writing: the newest version of each subject's key."
  @type current_keys :: %{{String.t(), String.t()} => {pos_integer(), binary()}}

  @doc "Whether `model`, a v2 contract's, declares an event with a personal field, at any depth."
  @spec declares?(map()) :: boolean()
  def declares?(model) do
    values = Codec.values(model.domain)
    Enum.any?(model.events, &Codec.personal?(&1.fields, values))
  end

  @typedoc """
  What `prepare/2` read and wrapped before the append lock: the subjects' newest
  keys, and a new key, already wrapped, for each subject that has none.
  """
  @type prepared :: %{
          subjects: [subject()],
          existing: current_keys(),
          created: %{
            {String.t(), String.t()} => {pos_integer(), binary(), Vault.kek_id(), binary()}
          }
        }

  @doc """
  The first half of `for_writing/2`, before the append lock: reads and unwraps the
  subjects' keys, and makes and wraps a key for each subject without one. Every
  call to the vault — a KMS's network round trip — happens here, so no writer
  waits on it.
  """
  @spec prepare(module(), [subject()]) :: prepared()
  def prepare(repo, subjects) do
    existing =
      repo
      |> for_reading(subjects)
      |> Enum.group_by(fn {{type, id, _v}, _key} -> {type, id} end)
      |> Map.new(fn {subject, keys} ->
        {{_, _, version}, key} = Enum.max_by(keys, fn {{_, _, v}, _} -> v end)
        {subject, {version, key}}
      end)

    created =
      for {type, id} <- subjects,
          subject = {Atom.to_string(type), id},
          not Map.has_key?(existing, subject),
          into: %{} do
        {type, id} = subject
        key = :crypto.strong_rand_bytes(32)
        {kek_id, wrapped} = Vault.wrap(key, context(type, id, 1))
        {subject, {1, key, kek_id, wrapped}}
      end

    %{subjects: subjects, existing: existing, created: created}
  end

  @doc """
  The second half, under the append lock: stores the keys `prepare/2` made, and
  returns the newest key of each subject. Creating them here is what keeps two
  dispatches from creating two keys for one subject.
  """
  @spec for_writing(module(), prepared()) :: current_keys()
  def for_writing(repo, %{existing: existing, created: created} = prepared) do
    rows =
      for {{type, id}, {version, _key, kek_id, wrapped}} <- created do
        %{
          subject_type: type,
          subject_id: id,
          key_version: version,
          kek_id: kek_id,
          wrapped_key: wrapped
        }
      end

    # Not logged: Ecto prints a query's parameters at `:debug`, and a wrapped key in a
    # log file, with the master key, reads the subject after its erasure.
    {inserted, _} =
      if rows == [],
        do: {0, nil},
        else: repo.insert_all(@keys, rows, on_conflict: :nothing, log: false)

    # Another dispatch created one between `prepare/2` and the lock; its key is the
    # one its events are sealed with, so read them all again. Rare, and the only
    # vault call under the lock.
    if inserted < length(rows) do
      for_writing(repo, %{prepare(repo, prepared.subjects) | created: %{}})
    else
      Map.merge(
        existing,
        Map.new(created, fn {subject, {v, key, _, _}} -> {subject, {v, key}} end)
      )
    end
  end

  @doc """
  Every data key of `subjects`, every version, in one query. A subject without keys
  is absent: its sealed fields read back as `EhOsContract.Erased`.
  """
  @spec for_reading(module(), [subject()]) :: keys()
  def for_reading(_repo, []), do: %{}

  def for_reading(repo, subjects) do
    {types, ids} =
      subjects
      |> Enum.uniq()
      |> Enum.map(fn {t, id} -> {Atom.to_string(t), id} end)
      |> Enum.unzip()

    repo.all(
      from(k in @keys,
        where:
          fragment(
            "(?, ?) IN (SELECT * FROM unnest(?::text[], ?::text[]))",
            k.subject_type,
            k.subject_id,
            type(^types, {:array, :string}),
            type(^ids, {:array, :string})
          ),
        select: {k.subject_type, k.subject_id, k.key_version, k.kek_id, k.wrapped_key}
      )
    )
    |> Map.new(fn {type, id, version, kek_id, wrapped} ->
      {{type, id, version}, unwrap!(type, version, kek_id, wrapped, id)}
    end)
  end

  @doc """
  The subjects among `subjects` that are erased, as `{type, id}` strings: the ones
  whose missing key means `EhOsContract.Erased`. One query, none for no subjects.
  """
  @spec erased_among(module(), [subject()]) :: MapSet.t({String.t(), String.t()})
  def erased_among(_repo, []), do: MapSet.new()

  def erased_among(repo, subjects) do
    {types, ids} =
      subjects
      |> Enum.uniq()
      |> Enum.map(fn {t, id} -> {Atom.to_string(t), id} end)
      |> Enum.unzip()

    repo.all(
      from(e in @erasures,
        where:
          fragment(
            "(?, ?) IN (SELECT * FROM unnest(?::text[], ?::text[]))",
            e.subject_type,
            e.subject_id,
            type(^types, {:array, :string}),
            type(^ids, {:array, :string})
          ),
        select: {e.subject_type, e.subject_id}
      )
    )
    |> MapSet.new()
  end

  defp unwrap!(type, version, kek_id, wrapped, id) do
    case Vault.unwrap(kek_id, wrapped, context(type, id, version)) do
      {:ok, key} ->
        key

      :error ->
        raise ArgumentError,
              "a data key of subject type #{inspect(type)} cannot be unwrapped with master key " <>
                "#{inspect(kek_id)}; is that key still in the vault?"
    end
  end

  @doc """
  The function `EhOsContract.Codec.encode/4` seals the personal fields of an event
  of `type` with, taking each subject's key from `keys`.
  """
  @spec sealer(current_keys(), String.t()) :: Codec.seal()
  def sealer(keys, type) do
    # Neither failure may say more than the field: `Map.fetch!/2` would print every
    # key of the dispatch, and `Jason.encode!/1` the value.
    fn path, {subject, id}, value ->
      {version, key} =
        case Map.fetch(keys, {Atom.to_string(subject), id}) do
          {:ok, current} ->
            current

          :error ->
            raise ArgumentError,
                  "field #{path} is personal to subject #{subject} #{inspect(id)}, whose key was " <>
                    "not prepared for this append"
        end

      json =
        case Jason.encode(value) do
          {:ok, json} ->
            json

          {:error, _} ->
            raise ArgumentError,
                  "field #{path} holds a value that cannot be written as JSON, such as text " <>
                    "that is not UTF-8"
        end

      iv = :crypto.strong_rand_bytes(12)
      aad = aad(type, path, subject, id, version)
      {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, json, aad, true)
      %{"$eh" => "enc1", "k" => version, "d" => Base.encode64(iv <> tag <> ct)}
    end
  end

  @doc """
  The function `EhOsContract.Codec.decode/4` opens the sealed fields of an event of
  `type` with. A subject `keys` has no key for opens as `:erased` when it is among
  `erased` (`erased_among/2`), and raises otherwise: a key that is gone without an
  erasure is a key store that is not the log's — a partial restore, another
  database — and reading on would turn good data into erased data for good.
  """
  @spec opener(keys(), String.t(), MapSet.t({String.t(), String.t()})) :: Codec.open()
  def opener(keys, type, erased \\ MapSet.new()) do
    fn
      path, {subject, id}, %{"$eh" => "enc1", "k" => version, "d" => data}
      when is_integer(version) and is_binary(data) ->
        case Map.fetch(keys, {Atom.to_string(subject), id, version}) do
          {:ok, key} -> open(key, data, aad(type, path, subject, id, version))
          :error -> missing(subject, id, version, erased)
        end

      _path, _subject, _other ->
        :error
    end
  end

  defp open(key, data, aad) do
    with {:ok, <<iv::binary-12, tag::binary-16, ct::binary>>} <- Base.decode64(data),
         json when is_binary(json) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ct, aad, tag, false),
         {:ok, value} <- Jason.decode(json) do
      {:ok, value}
    else
      # A ciphertext that does not open, which the codec reports as a field that
      # does not fit.
      _ -> :error
    end
  end

  defp missing(subject, id, version, erased) do
    if MapSet.member?(erased, {Atom.to_string(subject), id}) do
      :erased
    else
      raise ArgumentError,
            "the data key of subject #{subject} #{inspect(id)}, version #{version}, is missing, " <>
              "and the subject was never erased; the key store is not the one this log was " <>
              "written with"
    end
  end

  @doc """
  Rewraps, with the vault's current master key, every data key another master key
  wraps: `mix eh_os_contract.rewrap`. Returns how many it rewrapped. Each batch of
  `batch` keys is one transaction, and skips keys another run holds; when any key
  is left on another master key at the end, it raises, so "done" means none is.
  """
  @spec rewrap!(module(), pos_integer()) :: non_neg_integer()
  def rewrap!(repo, batch \\ 500) do
    current = Vault.current()
    count = rewrap!(repo, batch, current, 0)

    # A batch skips the keys another run holds, so an empty batch does not mean that
    # none is left; the old master key may only go when none is.
    case repo.one(from(k in @keys, where: k.kek_id != ^current, select: count())) do
      0 ->
        count

      left ->
        raise ArgumentError,
              "#{count} data keys rewrapped, and #{left} are still wrapped by another master key " <>
                "than #{inspect(current)} — another rewrap holds them, or wrote them meanwhile; " <>
                "run it again before the old master key leaves the vault"
    end
  end

  defp rewrap!(repo, batch, current, done) do
    {:ok, count} =
      repo.transaction(fn ->
        rows =
          repo.all(
            from(k in @keys,
              where: k.kek_id != ^current,
              limit: ^batch,
              lock: "FOR UPDATE SKIP LOCKED",
              select: {k.subject_type, k.subject_id, k.key_version, k.kek_id, k.wrapped_key}
            )
          )

        for {type, id, version, kek_id, wrapped} <- rows do
          context = context(type, id, version)
          key = unwrap!(type, version, kek_id, wrapped, id)
          {new_kek, new_wrapped} = Vault.wrap(key, context)

          # A vault that wraps with another key than the one it calls current would
          # have this pass over the same rows for ever.
          unless new_kek == current do
            raise ArgumentError,
                  "the vault wrapped with #{inspect(new_kek)} and calls #{inspect(current)} current"
          end

          repo.update_all(
            from(k in @keys,
              where: k.subject_type == ^type and k.subject_id == ^id and k.key_version == ^version
            ),
            [set: [kek_id: new_kek, wrapped_key: new_wrapped]],
            log: false
          )
        end

        length(rows)
      end)

    if count == 0, do: done, else: rewrap!(repo, batch, current, done + count)
  end

  # What a data key is bound to when wrapped: its row.
  defp context(type, id, version), do: "eh_os_contract.subject_key|#{type}|#{id}|#{version}"

  # What a sealed field is bound to: the event type, the field, the subject, the key.
  defp aad(type, path, subject, id, version), do: "#{type}|#{path}|#{subject}:#{id}|#{version}"
end
