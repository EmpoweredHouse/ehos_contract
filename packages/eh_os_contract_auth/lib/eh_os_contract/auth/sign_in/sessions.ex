defmodule EhOsContract.Auth.SignIn.Sessions do
  @moduledoc false

  # The rows of people signed in through EHOS (docs/adr/browser-session.md, S2, S3, S11), in the
  # tables of `EhOsContract.Auth.Migrations.V03`.
  #
  # The browser holds 32 random bytes, and the row their SHA-256 (S2). The refresh token, the ID
  # token and each credential are encrypted with the sign-in child's key, bound to the row's hash
  # and their column (S3); a value that does not decrypt ends the session, and its row is
  # deleted. The key is read from the child by its name inside each function, never passed in.
  # `create/2` is handed EHOS's tokens as the code exchange returned them, and checks their shape
  # first, by name and type only: a failed match, a guard or a `KeyError` further down would print
  # the map, or the key as an argument of `Plug.Crypto.MessageEncryptor.encrypt/4`.

  import Ecto.Query, only: [from: 2]

  alias EhOsContract.Auth.SignIn
  alias EhOsContract.Auth.SignIn.Cipher

  @sessions "eh_os_contract_auth_sessions"
  @credentials "eh_os_contract_auth_session_credentials"
  @token_bytes 32
  @fields [
    subject: "a string",
    sid: "a string",
    auth_time: "a DateTime",
    refresh_token: "a string",
    id_token: "a string"
  ]
  @credential_fields [resource: "a string", token: "a string", expires_at: "a DateTime"]
  # D-66: a sign-in lives at most twelve hours from `auth_time`, renewed or not.
  @absolute_limit_seconds 12 * 60 * 60

  @derive {Inspect, only: [:id, :subject, :sid, :auth_time]}
  defstruct [
    :id,
    :token_hash,
    :subject,
    :sid,
    :auth_time,
    :refresh_token,
    :id_token,
    :lease_holder,
    credentials: %{}
  ]

  @typedoc "A credential held for an application, by its address, or a refusal remembered."
  @type credential :: %{
          token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          refused_until: DateTime.t() | nil
        }

  @typedoc "A session, decrypted. Only its id, subject, sid and auth_time are inspected."
  @type t :: %__MODULE__{
          id: pos_integer(),
          token_hash: binary(),
          subject: String.t(),
          sid: String.t(),
          auth_time: DateTime.t(),
          refresh_token: String.t(),
          id_token: String.t(),
          lease_holder: String.t() | nil,
          credentials: %{String.t() => credential()}
        }

  @typedoc "What a code exchange gives a new session."
  @type signed_in :: %{
          subject: String.t(),
          sid: String.t(),
          auth_time: DateTime.t(),
          refresh_token: String.t(),
          id_token: String.t(),
          credential: %{resource: String.t(), token: String.t(), expires_at: DateTime.t()}
        }

  @doc false
  # Writes a new session and its first credential, and returns the token for the browser. Rows
  # past the absolute limit are deleted first, by a statement of their own (S11): no job cleans
  # them, and a wait on them does not hold the new sign-in's transaction.
  @spec create(atom(), signed_in()) :: {:ok, String.t()}
  def create(name, signed_in) do
    %{credential: credential} = signed_in = checked!(signed_in)
    key = SignIn.config(name).cipher_key
    token = :crypto.strong_rand_bytes(@token_bytes)
    hash = :crypto.hash(:sha256, token)
    limit = limit()
    repo = repo()

    session = %{
      token_hash: hash,
      subject: signed_in.subject,
      sid: signed_in.sid,
      auth_time: DateTime.truncate(signed_in.auth_time, :second),
      refresh_token: seal(signed_in.refresh_token, key, hash, "refresh_token"),
      id_token: seal(signed_in.id_token, key, hash, id_token_column(signed_in))
    }

    repo.delete_all(from(s in @sessions, where: s.auth_time < ^limit))

    {:ok, :ok} =
      repo.transaction(fn ->
        {1, [%{id: id}]} = repo.insert_all(@sessions, [session], returning: [:id])

        {1, _rows} =
          repo.insert_all(@credentials, [
            %{
              session_id: id,
              resource: credential.resource,
              token: seal(credential.token, key, hash, credential_column(credential.resource)),
              expires_at: credential.expires_at
            }
          ])

        :ok
      end)

    {:ok, Base.url_encode64(token, padding: false)}
  end

  @doc false
  # The session the browser's token names, decrypted. `{:error, :signed_out}` when there is none,
  # when the token is not one this package made, when it is past the absolute limit (D-66), the
  # next sign-in deleting its row, or when a value does not decrypt under the child's key, a
  # rotated `SECRET_KEY_BASE` for one, or for the row's plain columns; that row is deleted.
  @spec fetch(atom(), term()) :: {:ok, t()} | {:error, :signed_out}
  def fetch(name, token) do
    with {:ok, hash} <- hash(token),
         [row] <- repo().all(session_query(hash, limit())) do
      decrypt(row, credentials(row.id), SignIn.config(name).cipher_key, hash)
    else
      _none -> {:error, :signed_out}
    end
  end

  @doc false
  # Deletes the session the browser's token names, with its credentials. Deleting none is `:ok`:
  # signing out twice is not an error.
  @spec delete(term()) :: :ok
  def delete(token) do
    with {:ok, hash} <- hash(token) do
      repo().delete_all(from(s in @sessions, where: s.token_hash == ^hash))
    end

    :ok
  end

  @doc false
  # S4, step 2: takes the session's lease for `holder`, in one statement in autocommit, when it is
  # free or past its time by the database's clock, so replicas whose clocks disagree still agree.
  # `{:taken, previous}` names who held it before, `nil` when nobody did: a lease past its time
  # and never released is a holder that overran it or died mid-call, and whether its refresh token
  # was presented is unknown.
  @spec take_lease(t(), String.t(), pos_integer()) :: {:taken, String.t() | nil} | :busy
  def take_lease(%__MODULE__{id: id}, holder, lease_ms) do
    %{rows: rows} =
      repo().query!(
        """
        WITH previous AS (SELECT id, lease_holder FROM #{@sessions} WHERE id = $1 FOR UPDATE)
        UPDATE #{@sessions} AS s
        SET lease_holder = $2, lease_until = clock_timestamp() + $3 * interval '1 millisecond'
        FROM previous
        WHERE s.id = previous.id AND (s.lease_until IS NULL OR s.lease_until < clock_timestamp())
        RETURNING previous.lease_holder
        """,
        [id, holder, lease_ms]
      )

    case rows do
      [[previous]] -> {:taken, previous}
      [] -> :busy
    end
  end

  @doc false
  # After a renewal EHOS did not answer, the lease stays held under `as` for `ms`, so the session's
  # other requests do not each call EHOS again at once; it is released by expiring.
  @spec hold_off(t(), String.t(), String.t(), pos_integer()) :: :ok
  def hold_off(%__MODULE__{id: id}, holder, as, ms) do
    repo().query!(
      "UPDATE #{@sessions} SET lease_holder = $3, " <>
        "lease_until = clock_timestamp() + $4 * interval '1 millisecond' " <>
        "WHERE id = $1 AND lease_holder = $2",
      [id, holder, as, ms]
    )

    :ok
  end

  @doc false
  # Releases the lease `holder` holds, and nothing when another holds it now.
  @spec release(t(), String.t()) :: :ok
  def release(%__MODULE__{id: id}, holder) do
    repo().query!(
      "UPDATE #{@sessions} SET lease_holder = NULL, lease_until = NULL " <>
        "WHERE id = $1 AND lease_holder = $2",
      [id, holder]
    )

    :ok
  end

  @doc false
  # S4, step 5: writes a renewal and releases the lease in one short transaction, guarded by the
  # lease: `:lost` when `holder` no longer holds it, and then nothing is written. The ID token stays
  # bound to the row's subject, sid and auth_time, which a renewal does not change.
  @spec renewed(atom(), t(), String.t(), %{
          refresh_token: String.t(),
          id_token: String.t(),
          resource: String.t(),
          token: String.t(),
          expires_at: DateTime.t()
        }) :: :ok | :lost
  def renewed(name, %__MODULE__{} = session, holder, renewal) do
    key = SignIn.config(name).cipher_key
    hash = session.token_hash
    repo = repo()

    refresh_token = seal(renewal.refresh_token, key, hash, "refresh_token")
    id_token = seal(renewal.id_token, key, hash, id_token_column(session))
    credential = seal(renewal.token, key, hash, credential_column(renewal.resource))

    result =
      repo.transaction(fn ->
        {rows, _} =
          repo.update_all(
            from(s in @sessions, where: s.id == ^session.id and s.lease_holder == ^holder),
            set: [
              refresh_token: refresh_token,
              id_token: id_token,
              lease_holder: nil,
              lease_until: nil
            ]
          )

        if rows == 0, do: repo.rollback(:lost)

        repo.insert_all(
          @credentials,
          [
            %{
              session_id: session.id,
              resource: renewal.resource,
              token: credential,
              expires_at: renewal.expires_at,
              refused_until: nil
            }
          ],
          on_conflict: {:replace, [:token, :expires_at, :refused_until]},
          conflict_target: [:session_id, :resource]
        )

        :ok
      end)

    case result do
      {:ok, :ok} -> :ok
      {:error, :lost} -> :lost
    end
  end

  @doc false
  # Ends a session by its row: at `invalid_grant`, a lost refresh token or a lost lease (S5, S11).
  @spec end_session(t()) :: :ok
  def end_session(%__MODULE__{id: id}) do
    repo().delete_all(from(s in @sessions, where: s.id == ^id))
    :ok
  end

  defp checked!(signed_in) do
    credential = if is_map(signed_in), do: Map.get(signed_in, :credential)

    wrong =
      wrong(signed_in, @fields) ++
        Enum.map(wrong(credential, @credential_fields), &("credential." <> &1))

    if wrong != [] do
      raise ArgumentError,
            "a session to write needs #{Enum.join(wrong, ", ")}; no value it was given is shown"
    end

    signed_in
  end

  defp wrong(map, fields) when is_map(map) do
    for {field, type} <- fields, not type?(Map.get(map, field), type), do: "#{field} as #{type}"
  end

  defp wrong(_other, fields), do: Enum.map(fields, fn {field, type} -> "#{field} as #{type}" end)

  defp type?(value, "a string"), do: is_binary(value) and value != ""
  defp type?(value, "a DateTime"), do: match?(%DateTime{}, value)

  defp hash(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} when byte_size(raw) == @token_bytes -> {:ok, :crypto.hash(:sha256, raw)}
      _other -> :error
    end
  end

  defp hash(_token), do: :error

  defp session_query(hash, limit) do
    from(s in @sessions,
      where: s.token_hash == ^hash and s.auth_time >= ^limit,
      select: %{
        id: s.id,
        subject: s.subject,
        sid: s.sid,
        auth_time: type(s.auth_time, :utc_datetime),
        refresh_token: s.refresh_token,
        id_token: s.id_token,
        lease_holder: s.lease_holder
      }
    )
  end

  defp credentials(id) do
    repo().all(
      from(c in @credentials,
        where: c.session_id == ^id,
        select: %{
          resource: c.resource,
          token: c.token,
          expires_at: type(c.expires_at, :utc_datetime_usec),
          refused_until: type(c.refused_until, :utc_datetime_usec)
        }
      )
    )
  end

  defp decrypt(row, credentials, key, hash) do
    with {:ok, refresh_token} <- open(row.refresh_token, key, hash, "refresh_token"),
         {:ok, id_token} <- open(row.id_token, key, hash, id_token_column(row)),
         {:ok, credentials} <- open_credentials(credentials, key, hash) do
      {:ok,
       %__MODULE__{
         id: row.id,
         token_hash: hash,
         subject: row.subject,
         sid: row.sid,
         auth_time: row.auth_time,
         refresh_token: refresh_token,
         id_token: id_token,
         lease_holder: row.lease_holder,
         credentials: credentials
       }}
    else
      :error ->
        repo().delete_all(from(s in @sessions, where: s.id == ^row.id))
        {:error, :signed_out}
    end
  end

  defp open_credentials(credentials, key, hash) do
    Enum.reduce_while(credentials, {:ok, %{}}, fn credential, {:ok, acc} ->
      case open(credential.token, key, hash, credential_column(credential.resource)) do
        {:ok, token} ->
          value = %{credential | token: token} |> Map.delete(:resource)
          {:cont, {:ok, Map.put(acc, credential.resource, value)}}

        :error ->
          {:halt, :error}
      end
    end)
  end

  defp seal(value, key, hash, column),
    do: Cipher.encrypt(value, key, Cipher.bound_to(hash, column))

  defp open(nil, _key, _hash, _column), do: {:ok, nil}

  defp open(value, key, hash, column),
    do: Cipher.decrypt(value, key, Cipher.bound_to(hash, column))

  # The ID token is bound to the plain columns that say whose session the row is, so a writer who
  # changes `subject`, `sid` or `auth_time` makes it a row that does not decrypt, not someone else's.
  defp id_token_column(%{subject: subject, sid: sid, auth_time: auth_time}) do
    seconds = auth_time |> DateTime.truncate(:second) |> DateTime.to_unix()
    "id_token " <> Jason.encode!([subject, sid, seconds])
  end

  defp limit, do: DateTime.add(EhOsContract.Clock.now(), -@absolute_limit_seconds)

  # A credential is bound to the application it is for, so one moved to another application's
  # row does not decrypt either.
  defp credential_column(resource), do: "credential " <> resource

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
