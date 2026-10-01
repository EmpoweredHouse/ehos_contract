if Code.ensure_loaded?(Plug.Conn) do
  defmodule EhOsContract.Plug do
    @moduledoc """
    The commands, recordings and queries of v2 contracts over HTTP, under the names
    EHOS grants them by (v2 §16, D10 and D14):

        # in the host's router, after whatever verifies the credential
        forward "/api", EhOsContract.Plug, contracts: [Rehmed.Contracts.VisitSettlement]

        POST /api/commands/rehmed.record_payment   {"visit_id": "w-1", "method": "card", "amount": 20000}
        POST /api/records/rehmed.patient_arrived   {"visit_id": "w-1"}
        GET  /api/queries/rehmed.open_visits_for_clinic?clinic_id=7

    **It authenticates nobody.** The actor is `conn.assigns.eh_os_contract_actor`,
    an `EhOsContract.Actor` that the plug in front of this one built from a
    credential it verified — `eh_os_contract_auth`'s, for EHOS's. Without one the
    answer is 401. A `:system` actor is the application's own code and never comes
    over HTTP, so one found there is refused too.

    It reads the body, or the query string, and the headers, and hands them to
    `EhOsContract.call/3`, which decodes them against the declaration's fields and
    goes through `EhOsContract.dispatch/3`, `EhOsContract.record/3` or
    `EhOsContract.query/3`, so everything they check is checked here the same way;
    what is left to this module is HTTP.
    An `idempotency-key` header becomes the command's idempotency key — the
    caller's own, since a key belongs to the actor who sent it — and an
    `x-correlation-id` header its correlation.

    **Whether the caller may make the call is answered first**, by `call/3`. A
    request that fails before dispatch or query would run — a body that is not an
    object, fields that do not decode, a correlation id that is not a UUID — is asked
    of the `EhOsContract.Authorizer` all the same, as the call would have been: a
    caller without the capability gets 403, not a description of the declaration's
    fields, and every request is one decision for the `Authorizer` to record.

    | Outcome | Status | Body |
    | --- | --- | --- |
    | accepted | 200 | `command_id`, `identity` (the unit's, the one the library gave when the command created it), `positions`, `position`, `duplicate`, and each event's `type` and `position` |
    | query answered | 200 | `rows`, or `row`, in the log's form; an erased personal field is `null` |
    | rejected on an invariant | 422 | `{"rejected": "<invariant>"}` |
    | fields that do not fit | 422 | `{"invalid": {"<field>": "required" \\| "type" \\| "generated" \\| "<invariant>"}}` — `generated` for an identity sent with a command that creates its aggregate, which the library gives; an invariant's name for a value that breaks it (plan EL2b) |
    | refused | 403 | `{"refused": "<reason>"}` |
    | no actor | 401 | `{"error": "no_actor"}` |
    | a command that creates its aggregate, without an `idempotency-key` | 422 | `{"error": "idempotency_key_required"}` |
    | conflict, or a reused key | 409 | `{"error": "<reason>"}` |
    | personal data of an erased subject | 410 | `{"error": "subject_erased"}` |
    | a recording for a unit no command created (its identity is the library's) | 404 | `{"error": "not_created"}` |
    | no such capability | 404 | `{"error": "not_found"}` |

    No body ever carries a field value the caller did not send: a problem names
    the field, a refusal its reason (v2 §17).
    """

    @behaviour Plug

    import Plug.Conn

    alias EhOsContract.{Codec, Dispatcher, Model, Receipt, Rejection}

    @doc "Takes `contracts:`, the contracts whose commands, recordings and queries it serves."
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
        {"POST", ["records", capability]} -> serve(conn, contracts, :record, capability)
        {"GET", ["queries", capability]} -> serve(conn, contracts, :query, capability)
        _ -> reply(conn, 404, %{error: "not_found"})
      end
    end

    defp serve(conn, contracts, kind, capability) do
      case Dispatcher.route(contracts, kind, capability) do
        {:ok, model, declaration} ->
          values = Codec.values(model.domain)
          fields = if kind == :query, do: declaration.params, else: declaration.fields
          {conn, input, unread} = input(conn, kind, fields, values)

          opts =
            [actor: conn.assigns[:eh_os_contract_actor], contracts: [model.module]]
            |> headers(conn, kind)

          answer(
            conn,
            kind,
            model,
            declaration,
            values,
            unread,
            call(kind, capability, input, opts)
          )

        {:error, :not_found} ->
          reply(conn, 404, %{error: "not_found"})
      end
    end

    # Whether the caller may is answered inside, before what is wrong with what it sent.
    defp call(kind, capability, input, opts),
      do: EhOsContract.call({kind, capability}, input, opts)

    defp headers(opts, _conn, :query), do: opts

    defp headers(opts, conn, _command_or_record) do
      opts
      |> put_header(conn, :idempotency_key, "idempotency-key")
      |> put_header(conn, :correlation_id, "x-correlation-id")
    end

    defp answer(conn, :query, model, declaration, values, _unread, {:ok, answer}) do
      read_model = Enum.find(model.read_models, &(&1.name == declaration.reads))
      encode = &Codec.encode(read_model.fields, &1, values)

      if declaration.returns == :one,
        do: reply(conn, 200, %{row: answer && encode.(answer)}),
        else: reply(conn, 200, %{rows: Enum.map(answer, encode)})
    end

    defp answer(conn, _kind, _model, _declaration, _values, _unread, {:error, :no_actor}),
      do: reply(conn, 401, %{error: "no_actor"})

    # What the body was, which only this door knows: unreadable, or not a JSON object.
    defp answer(conn, _kind, _model, _declaration, _values, unread, {:error, :not_an_object}),
      do: reply(conn, 400, %{error: unread || "body_is_not_a_json_object"})

    defp answer(
           conn,
           _kind,
           _model,
           _declaration,
           _values,
           _unread,
           {:error, :correlation_id_is_not_a_uuid}
         ),
         do: reply(conn, 400, %{error: "correlation_id_is_not_a_uuid"})

    defp answer(conn, _kind, model, _declaration, _values, _unread, result),
      do: reply_to(conn, model, result)

    defp reply_to(conn, model, result) do
      case result do
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

    # A broken invariant is named where `required` or `type` would be: D9 keeps those
    # words from being an invariant's name.
    defp refused(conn, {:invalid, problems}) do
      invalid =
        Map.new(problems, fn
          {field, {:invariant, invariant}} -> {field, invariant}
          problem -> problem
        end)

      reply(conn, 422, %{invalid: invalid})
    end

    defp refused(conn, :idempotency_key_required),
      do: reply(conn, 422, %{error: :idempotency_key_required})

    defp refused(conn, reason) when reason in [:conflict, :idempotency_key_reused],
      do: reply(conn, 409, %{error: reason})

    defp refused(conn, :subject_erased), do: reply(conn, 410, %{error: :subject_erased})

    # A recording for a unit whose identity the library gives, and that no command
    # created: there is no such unit, which is not a refusal of the caller.
    defp refused(conn, :not_created), do: reply(conn, 404, %{error: :not_created})

    defp refused(conn, reason), do: reply(conn, 403, %{refused: reason})

    # The input as this door read it, and, when it could not read an object, what the
    # body was instead, for the answer once the caller may know it.
    defp input(conn, :query, fields, values) do
      {conn, input} = decode_query_params(conn, fields, values)
      {conn, input, nil}
    end

    defp input(%{body_params: %Plug.Conn.Unfetched{}} = conn, :command, _fields, _values) do
      case read_body(conn) do
        {:ok, "", conn} ->
          {conn, %{}, nil}

        {:ok, body, conn} ->
          case Jason.decode(body) do
            {:ok, %{} = decoded} -> {conn, decoded, nil}
            _not_an_object -> {conn, nil, "body_is_not_a_json_object"}
          end

        _unreadable ->
          {conn, nil, "unreadable_body"}
      end
    end

    defp input(conn, :command, _fields, _values), do: {conn, conn.body_params, nil}
    defp input(conn, :record, fields, values), do: input(conn, :command, fields, values)

    @doc false
    @spec decode_query_params(Plug.Conn.t(), [map()], map()) :: {Plug.Conn.t(), map()}
    def decode_query_params(conn, fields, values) do
      conn = fetch_query_params(conn)
      pairs = Enum.to_list(URI.query_decoder(conn.query_string))

      input =
        Enum.reduce(fields, conn.query_params, fn field, params ->
          if list_type?(field.type, values) do
            name = Atom.to_string(field.name)
            repeated = for {^name, value} <- pairs, do: value
            if repeated == [], do: params, else: Map.put(params, name, repeated)
          else
            params
          end
        end)

      {conn, input}
    end

    defp list_type?({:list, _inner}, _values), do: true

    defp list_type?(type, values) when is_atom(type) and is_map_key(values, type) do
      case Map.fetch!(values, type) do
        %{type: nil} -> false
        %{type: inner} -> list_type?(inner, values)
      end
    end

    defp list_type?(_type, _values), do: false

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
