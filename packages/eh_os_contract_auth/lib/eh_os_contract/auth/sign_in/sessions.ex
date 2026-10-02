defmodule EhOsContract.Auth.SignIn.Sessions do
  @moduledoc false

  # The rows of people signed in through EHOS (docs/adr/browser-session.md, S2, S3, S11), in the
  # tables of `EhOsContract.Auth.Migrations.V03`.
  #
  # The browser holds 32 random bytes, and the row their SHA-256 (S2). The refresh token, the ID
  # token and each credential are encrypted with the sign-in child's key, bound to the row's hash
  # and their column (S3); a value that does not decrypt ends the session, and its row is
  # deleted. The key is read from the child by its name inside each function, never passed in, so
  # no frame a crash prints holds it. `create/2` is handed EHOS's tokens as the code exchange
  # returned them; it matches nothing on them, and raises only when the database does.

  import Ecto.Query, only: [from: 2]

  alias EhOsContract.Auth.SignIn
  alias EhOsContract.Auth.SignIn.Cipher

  @sessions "eh_os_contract_auth_sessions"
  @credentials "eh_os_contract_auth_session_credentials"
  @token_bytes 32
  # D-66: a sign-in lives at most twelve hours from `auth_time`, renewed or not.
  @absolute_limit_seconds 12 * 60 * 60

  @derive {Inspect, only: [:id, :subject, :sid, :auth_time]}
  defstruct [:id, :subject, :sid, :auth_time, :refresh_token, :id_token, credentials: %{}]

  @typedoc "A credential held for an application, by its address, or a refusal remembered."
  @type credential :: %{
          token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          refused_until: DateTime.t() | nil
        }

  @typedoc "A session, decrypted. Only its id, subject, sid and auth_time are inspected."
  @type t :: %__MODULE__{
          id: pos_integer(),
          subject: String.t(),
          sid: String.t(),
          auth_time: DateTime.t(),
          refresh_token: String.t(),
          id_token: String.t(),
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
  # past the absolute limit go in the same transaction (S11): no job cleans them.
  @spec create(atom(), signed_in()) :: {:ok, String.t()}
  def create(name, %{credential: credential} = signed_in) do
    key = SignIn.config(name).cipher_key
    token = :crypto.strong_rand_bytes(@token_bytes)
    hash = :crypto.hash(:sha256, token)
    limit = DateTime.add(EhOsContract.Clock.now(), -@absolute_limit_seconds)
    repo = repo()

    session = %{
      token_hash: hash,
      subject: signed_in.subject,
      sid: signed_in.sid,
      auth_time: DateTime.truncate(signed_in.auth_time, :second),
      refresh_token: seal(signed_in.refresh_token, key, hash, "refresh_token"),
      id_token: seal(signed_in.id_token, key, hash, "id_token")
    }

    {:ok, :ok} =
      repo.transaction(fn ->
        repo.delete_all(from(s in @sessions, where: s.auth_time < ^limit))
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
  # when the token is not one this package made, or when a value does not decrypt under the
  # child's key, a rotated `SECRET_KEY_BASE` for one; that row is deleted.
  @spec fetch(atom(), term()) :: {:ok, t()} | {:error, :signed_out}
  def fetch(name, token) do
    with {:ok, hash} <- hash(token),
         [row] <- repo().all(session_query(hash)) do
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

  defp hash(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} when byte_size(raw) == @token_bytes -> {:ok, :crypto.hash(:sha256, raw)}
      _other -> :error
    end
  end

  defp hash(_token), do: :error

  defp session_query(hash) do
    from(s in @sessions,
      where: s.token_hash == ^hash,
      select: %{
        id: s.id,
        subject: s.subject,
        sid: s.sid,
        auth_time: type(s.auth_time, :utc_datetime),
        refresh_token: s.refresh_token,
        id_token: s.id_token
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
         {:ok, id_token} <- open(row.id_token, key, hash, "id_token"),
         {:ok, credentials} <- open_credentials(credentials, key, hash) do
      {:ok,
       %__MODULE__{
         id: row.id,
         subject: row.subject,
         sid: row.sid,
         auth_time: row.auth_time,
         refresh_token: refresh_token,
         id_token: id_token,
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

  # A credential is bound to the application it is for, so one moved to another application's
  # row does not decrypt either.
  defp credential_column(resource), do: "credential " <> resource

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end
