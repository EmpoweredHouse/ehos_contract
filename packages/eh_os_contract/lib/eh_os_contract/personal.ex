defmodule EhOsContract.Personal do
  @moduledoc """
  Personal data in the log (v2 §14): each subject's data key, and the personal
  fields of events sealed with it.

  **A key per subject.** A subject — a person whose data may be erased, `subject
  :patient` in the domain — gets a data key, 32 random bytes, the first time an
  event carries its personal data. The key is stored in
  `eh_os_contract_subject_keys` only wrapped by `EhOsContract.Vault`, and it is
  created under the append lock, so two dispatches never create two. Deleting a
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

  @doc """
  The newest data key of each of `subjects`, creating the ones that do not exist.
  Called under the append lock.
  """
  @spec for_writing(module(), [subject()]) :: current_keys()
  def for_writing(_repo, []), do: %{}

  def for_writing(repo, subjects) do
    existing =
      repo
      |> for_reading(subjects)
      |> Enum.group_by(fn {{type, id, _v}, _key} -> {type, id} end)
      |> Map.new(fn {subject, keys} ->
        {{_, _, version}, key} = Enum.max_by(keys, fn {{_, _, v}, _} -> v end)
        {subject, {version, key}}
      end)

    missing =
      for {type, id} <- subjects,
          subject = {Atom.to_string(type), id},
          not Map.has_key?(existing, subject),
          uniq: true,
          do: subject

    created =
      Map.new(missing, fn {type, id} ->
        key = :crypto.strong_rand_bytes(32)
        {kek_id, wrapped} = Vault.wrap(key, context(type, id, 1))
        {{type, id}, {1, key, kek_id, wrapped}}
      end)

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

    {inserted, _} = repo.insert_all(@keys, rows, on_conflict: :nothing)

    # Only a writer outside the append lock could have inserted one first; its key
    # is the one to use, so read them back.
    if inserted < length(rows) do
      for_writing(repo, subjects)
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
    fn path, {subject, id}, value ->
      {version, key} = Map.fetch!(keys, {Atom.to_string(subject), id})
      iv = :crypto.strong_rand_bytes(12)
      aad = aad(type, path, subject, id, version)
      json = Jason.encode!(value)
      {ct, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, json, aad, true)
      %{"$eh" => "enc1", "k" => version, "d" => Base.encode64(iv <> tag <> ct)}
    end
  end

  @doc """
  The function `EhOsContract.Codec.decode/4` opens the sealed fields of an event of
  `type` with: `:erased` when `keys` has no key for the subject.
  """
  @spec opener(keys(), String.t()) :: Codec.open()
  def opener(keys, type) do
    fn
      path, {subject, id}, %{"$eh" => "enc1", "k" => version, "d" => data}
      when is_integer(version) and is_binary(data) ->
        with {:ok, key} <- Map.fetch(keys, {Atom.to_string(subject), id, version}),
             {:ok, <<iv::binary-12, tag::binary-16, ct::binary>>} <- Base.decode64(data),
             json when is_binary(json) <-
               :crypto.crypto_one_time_aead(
                 :aes_256_gcm,
                 key,
                 iv,
                 ct,
                 aad(type, path, subject, id, version),
                 tag,
                 false
               ) do
          Jason.decode(json)
        else
          # No key: the subject is erased. Anything else is a ciphertext that does
          # not open, which the codec reports as a field that does not fit.
          :error ->
            if Map.has_key?(keys, {Atom.to_string(subject), id, version}),
              do: :error,
              else: :erased

          _ ->
            :error
        end

      _path, _subject, _other ->
        :error
    end
  end

  @doc """
  Rewraps, with the vault's current master key, every data key another master key
  wraps: `mix eh_os_contract.rewrap`. Returns how many it rewrapped. Each batch of
  `batch` keys is one transaction.
  """
  @spec rewrap!(module(), pos_integer()) :: non_neg_integer()
  def rewrap!(repo, batch \\ 500), do: rewrap!(repo, batch, Vault.current(), 0)

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
            set: [kek_id: new_kek, wrapped_key: new_wrapped]
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
