if Code.ensure_loaded?(Plug.Conn) do
  defmodule EhOsContract.Plug do
    @moduledoc """
    The commands and queries of v2 contracts over HTTP, under the names EHOS grants
    them by (v2 §16, D10 and D14):

        # in the host's router, after whatever verifies the credential
        forward "/api", EhOsContract.Plug, contracts: [Rehmed.Contracts.VisitSettlement]

        POST /api/commands/rehmed.record_payment   {"visit_id": "w-1", "method": "card", "amount": 20000}
        GET  /api/queries/rehmed.open_visits_for_clinic?clinic_id=7

    **It authenticates nobody.** The actor is `conn.assigns.eh_os_contract_actor`,
    an `EhOsContract.Actor` that the plug in front of this one built from a
    credential it verified — `eh_os_contract_auth`'s, for EHOS's. Without one the
    answer is 401. A `:system` actor is the application's own code and never comes
    over HTTP, so one found there is refused too.

    The body, or the query string, is decoded against the declaration's fields
    (`EhOsContract.Codec`), and the call goes through `EhOsContract.dispatch/3` or
    `EhOsContract.query/3`, so everything they check is checked here the same way.
    An `idempotency-key` header becomes the command's idempotency key, and an
    `x-correlation-id` header its correlation.

    **Whether the caller may make the call is answered first.** A request that fails
    before dispatch or query would run — a body that is not an object, fields that do
    not decode, a correlation id that is not a UUID — is asked of the
    `EhOsContract.Authorizer` all the same, as the call would have been: a caller
    without the capability gets 403, not a description of the declaration's fields,
    and every request is one decision for the `Authorizer` to record.

    | Outcome | Status | Body |
    | --- | --- | --- |
    | accepted | 200 | `command_id`, `identity` (the unit's, the one the library gave when the command created it), `positions`, `position`, `duplicate`, and each event's `type` and `position` |
    | query answered | 200 | `rows`, or `row`, in the log's form; an erased personal field is `null` |
    | rejected on an invariant | 422 | `{"rejected": "<invariant>"}` |
    | fields that do not fit | 422 | `{"invalid": {"<field>": "required" \\| "type" \\| "generated"}}` — `generated` for an identity sent with a command that creates its aggregate, which the library gives |
    | refused | 403 | `{"refused": "<reason>"}` |
    | no actor | 401 | `{"error": "no_actor"}` |
    | conflict, or a reused key | 409 | `{"error": "<reason>"}` |
    | personal data of an erased subject | 410 | `{"error": "subject_erased"}` |
    | no such capability | 404 | `{"error": "not_found"}` |

    No body ever carries a field value the caller did not send: a problem names
    the field, a refusal its reason (v2 §17).
    """

    @behaviour Plug

    import Plug.Conn

    alias EhOsContract.{Actor, Codec, Dispatcher, Model, Receipt, Rejection}

    @doc "Takes `contracts:`, the v2 contracts whose commands and queries it serves."
    @impl true
    @spec init(keyword()) :: %{contracts: [module()]}
    def init(opts) do
      contracts = Keyword.fetch!(opts, :contracts)
      %{contracts: List.wrap(contracts)}
    end

    @doc "Serves one request, or answers 404 for a path it does not route."
    @impl true
    @spec call(Plug.Conn.t(), %{contracts: [module()]}) :: Plug.Conn.t()
    def call(conn, %{contracts: contracts}) do
      case {conn.method, conn.path_info} do
        {"POST", ["commands", capability]} -> serve(conn, contracts, :command, capability)
        {"GET", ["queries", capability]} -> serve(conn, contracts, :query, capability)
        _ -> reply(conn, 404, %{error: "not_found"})
      end
    end

    defp serve(conn, contracts, kind, capability) do
      with {:ok, model, declaration} <- route(contracts, kind, capability),
           {:ok, actor} <- actor(conn) do
        values = Codec.values(model.domain)

        case prepare(conn, model, kind, declaration, values) do
          {:ok, conn, struct} ->
            respond(conn, kind, model, declaration, struct, actor, values)

          # Whether the caller may make this call is answered before what is wrong
          # with it, so a refusal is a refusal whatever was sent, and has its row.
          {:error, conn, input, status, body} ->
            case Dispatcher.permit_undecoded(model, kind, declaration, actor, input) do
              :ok -> reply(conn, status, body)
              {:error, reason} -> refused(conn, reason)
            end
        end
      else
        {:error, status, body} -> reply(conn, status, body)
      end
    end

    # The request as dispatch or query takes it, or what is wrong with it and the
    # input as it was sent.
    defp prepare(conn, model, kind, declaration, values) do
      fields = if kind == :command, do: declaration.fields, else: declaration.params

      with {:ok, conn, input} <- input(conn, kind),
           {:ok, decoded} <- decode(conn, fields, input, values, kind),
           :ok <- correlation(conn, input, kind) do
        {:ok, conn, struct!(Model.module_for(model, kind, declaration.name), decoded)}
      end
    end

    defp decode(conn, fields, input, values, kind) do
      case Codec.decode(fields, input, values, strings: kind == :query) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, problems} -> {:error, conn, input, 422, %{invalid: Map.new(problems)}}
      end
    end

    defp correlation(conn, input, :command) do
      case get_req_header(conn, "x-correlation-id") do
        [] ->
          :ok

        [id | _] ->
          case Ecto.UUID.cast(id) do
            {:ok, _} -> :ok
            :error -> {:error, conn, input, 400, %{error: "correlation_id_is_not_a_uuid"}}
          end
      end
    end

    defp correlation(_conn, _input, :query), do: :ok

    defp respond(conn, :command, model, _declaration, command, actor, _values) do
      opts =
        [actor: actor]
        |> put_header(conn, :idempotency_key, "idempotency-key")
        |> put_header(conn, :correlation_id, "x-correlation-id")

      dispatch(conn, model, command, opts)
    end

    defp respond(conn, :query, model, declaration, params, actor, values) do
      case EhOsContract.query(model.module, params, actor: actor) do
        {:ok, answer} ->
          read_model = Enum.find(model.read_models, &(&1.name == declaration.reads))
          encode = &Codec.encode(read_model.fields, &1, values)

          if declaration.returns == :one,
            do: reply(conn, 200, %{row: answer && encode.(answer)}),
            else: reply(conn, 200, %{rows: Enum.map(answer, encode)})

        {:error, reason} ->
          refused(conn, reason)
      end
    end

    defp dispatch(conn, model, command, opts) do
      case EhOsContract.dispatch(model.module, command, opts) do
        {:ok, %Receipt{} = receipt} ->
          reply(conn, 200, %{
            command_id: receipt.command_id,
            identity: receipt.identity,
            positions: receipt.positions,
            position: receipt.position,
            duplicate: receipt.duplicate,
            events:
              for(
                event <- receipt.events,
                do: %{type: type(model, event), position: event.__meta__.position}
              )
          })

        {:error, %Rejection{invariant: invariant}} ->
          reply(conn, 422, %{rejected: invariant})

        {:error, reason} ->
          refused(conn, reason)
      end
    end

    defp refused(conn, {:invalid, problems}), do: reply(conn, 422, %{invalid: Map.new(problems)})

    defp refused(conn, reason) when reason in [:conflict, :idempotency_key_reused],
      do: reply(conn, 409, %{error: reason})

    defp refused(conn, :subject_erased), do: reply(conn, 410, %{error: :subject_erased})

    defp refused(conn, reason), do: reply(conn, 403, %{refused: reason})

    # The declaration a capability names, among the contracts this plug serves.
    defp route(contracts, kind, capability) do
      Enum.find_value(contracts, {:error, 404, %{error: "not_found"}}, fn contract ->
        model = Model.fetch(contract)

        case Map.get(Model.capabilities(model), capability) do
          %{kind: ^kind, name: name} ->
            declarations = if kind == :command, do: model.commands, else: model.queries
            {:ok, model, Enum.find(declarations, &(&1.name == name))}

          _ ->
            nil
        end
      end)
    end

    defp actor(conn) do
      case conn.assigns[:eh_os_contract_actor] do
        %Actor{kind: :credential} = actor -> {:ok, actor}
        _none_or_not_a_credential -> {:error, 401, %{error: "no_actor"}}
      end
    end

    defp input(conn, :query) do
      conn = fetch_query_params(conn)
      {:ok, conn, conn.query_params}
    end

    defp input(%{body_params: %Plug.Conn.Unfetched{}} = conn, :command) do
      case read_body(conn) do
        {:ok, "", conn} ->
          {:ok, conn, %{}}

        {:ok, body, conn} ->
          case Jason.decode(body) do
            {:ok, %{} = decoded} -> {:ok, conn, decoded}
            _ -> {:error, conn, %{}, 400, %{error: "body_is_not_a_json_object"}}
          end

        _ ->
          {:error, conn, %{}, 400, %{error: "unreadable_body"}}
      end
    end

    defp input(conn, :command), do: {:ok, conn, conn.body_params}

    defp put_header(opts, conn, key, header) do
      case get_req_header(conn, header) do
        [value | _] -> Keyword.put(opts, key, value)
        [] -> opts
      end
    end

    defp type(model, %module{}) do
      Enum.find_value(model.events, fn event ->
        Model.module_for(model, :event, event.name) == module && event.type
      end)
    end

    defp reply(conn, status, body) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(body))
      |> halt()
    end
  end
end
