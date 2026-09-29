defmodule EhOsContract.OpenAPI do
  @moduledoc """
  An OpenAPI document generated from a v2 contract's HTTP capabilities.

  Paths are relative to the mount of `EhOsContract.Plug`: a human command is
  `POST /commands/<capability>` and a query is
  `GET /queries/<capability>`. Commands that only application code may issue have
  no capability and therefore no path. Recorded events are intentionally absent:
  this E10 projection is the D10 command-and-query API, not a description of every
  route the plug can serve.

  The document uses OpenAPI 3.1.2 so its schemas are JSON Schema and can share the
  exact field projection used by `EhOsContract.AsyncAPI`. It describes a bearer
  credential without claiming which issuer or token format the host uses; the host
  owns authentication, while `EhOsContract.Plug` receives the verified actor.

  Each contract has its own document and digest. The digest covers the generated
  document without the digest key, so a consumer can compare a build artifact with
  the description served by an instance.
  """

  alias EhOsContract.{JsonSchema, Model}

  @openapi_version "3.1.2"

  @doc "The OpenAPI document for one v2 contract, including its digest."
  @spec document(module() | map()) :: map()
  def document(contract) do
    body = body(contract)
    put_in(body, ["info", "x-eh-os-contract-digest"], digest(body))
  end

  @doc "The stable digest of a document, ignoring the value already in its digest key."
  @spec digest(map()) :: String.t()
  def digest(document) do
    document
    |> update_in(["info"], &Map.delete(&1, "x-eh-os-contract-digest"))
    |> EhOsContract.Digest.document_hash()
  end

  @doc "Every registered v2 contract, with its contract version and OpenAPI digest."
  @spec index() :: [map()]
  def index do
    for contract <- EhOsContract.Registry.v2_contracts() do
      document = document(contract)

      %{
        "contract" => inspect(contract),
        "version" => Model.fetch(contract).version,
        "digest" => document["info"]["x-eh-os-contract-digest"]
      }
    end
    |> Enum.sort_by(& &1["contract"])
  end

  defp body(contract) do
    model = Model.fetch(contract)
    domain = Model.fetch(model.domain)

    %{
      "openapi" => @openapi_version,
      "jsonSchemaDialect" => "https://spec.openapis.org/oas/3.1/dialect/base",
      "info" => %{
        "title" => inspect(model.module),
        "version" => model.version,
        "x-eh-os-contract-engine" => EhOsContract.version()
      },
      "paths" => paths(model, domain),
      "security" => [%{"bearerAuth" => []}],
      "components" => %{
        "securitySchemes" => %{
          "bearerAuth" => %{
            "type" => "http",
            "scheme" => "bearer",
            "description" => "A credential verified by the host before EhOsContract.Plug."
          }
        }
      }
    }
  end

  defp paths(model, domain) do
    for {capability, access} <- Model.capabilities(model),
        access.kind in [:command, :query],
        into: %{} do
      case access.kind do
        :command -> command_path(model, domain, capability, access)
        :query -> query_path(model, domain, capability, access)
      end
    end
  end

  defp command_path(model, domain, capability, access) do
    command = Enum.find(model.commands, &(&1.name == access.name))
    unit = Enum.find(model.units, &(&1.name == command.unit))
    fields = command_fields(command, unit)

    {"/commands/#{capability}",
     %{
       "post" =>
         operation(command, capability, access)
         |> Map.merge(%{
           "operationId" => "command_#{command.name}",
           "parameters" => command_headers(command),
           "requestBody" => %{
             "required" => true,
             "content" => %{
               "application/json" => %{"schema" => JsonSchema.object(fields, domain)}
             }
           },
           "responses" => command_responses()
         })
     }}
  end

  defp query_path(model, domain, capability, access) do
    query = Enum.find(model.queries, &(&1.name == access.name))
    read_model = Enum.find(model.read_models, &(&1.name == query.reads))

    {"/queries/#{capability}",
     %{
       "get" =>
         operation(query, capability, access)
         |> Map.merge(%{
           "operationId" => "query_#{query.name}",
           "parameters" => Enum.map(query.params, &query_parameter(&1, domain)),
           "responses" => query_responses(query, read_model, domain)
         })
     }}
  end

  defp operation(declaration, capability, access) do
    %{
      "summary" => declaration.label,
      "x-eh-os-contract-capability" => capability,
      "x-eh-os-contract-roles" => access.roles,
      "x-eh-os-contract-scope" => access.scope && to_string(access.scope)
    }
  end

  defp command_fields(command, %{generated: generated, identity: identity})
       when not is_nil(generated) do
    if Map.get(command, :creates, false),
      do: Enum.reject(command.fields, &(&1.name in identity)),
      else: command.fields
  end

  defp command_fields(command, _unit), do: command.fields

  defp command_headers(command) do
    [
      %{
        "name" => "idempotency-key",
        "in" => "header",
        "required" => Map.get(command, :creates, false),
        "schema" => %{"type" => "string"},
        "description" => "Idempotency key; required when the command creates its aggregate."
      },
      %{
        "name" => "x-correlation-id",
        "in" => "header",
        "required" => false,
        "schema" => %{"type" => "string", "format" => "uuid"}
      }
    ]
  end

  defp query_parameter(field, domain) do
    parameter = %{
      "name" => to_string(field.name),
      "in" => "query",
      "required" => not Map.get(field, :optional, false),
      "schema" => JsonSchema.field(field, domain)
    }

    case query_shape(field.type, domain) do
      :object -> Map.merge(parameter, %{"style" => "deepObject", "explode" => true})
      _scalar_or_array -> Map.merge(parameter, %{"style" => "form", "explode" => true})
    end
  end

  defp query_shape({:list, _inner}, _domain), do: :array

  defp query_shape(type, domain) when is_atom(type) do
    case Enum.find(domain.values, &(&1.name == type)) do
      %{type: nil} -> :object
      %{type: inner} -> query_shape(inner, domain)
      nil -> :scalar
    end
  end

  defp query_shape(_type, _domain), do: :scalar

  defp command_responses do
    %{
      "200" => %{"description" => "Command accepted", "content" => json(receipt_schema())},
      "400" => %{"description" => "Invalid JSON body or correlation identifier"},
      "401" => %{"description" => "No verified actor"},
      "403" => %{"description" => "Capability or scope refused"},
      "404" => %{"description" => "Capability not found"},
      "409" => %{"description" => "Conflict or reused idempotency key"},
      "410" => %{"description" => "Personal-data subject erased"},
      "422" => %{
        "description" => "Invalid fields, missing idempotency key, or invariant rejection"
      }
    }
  end

  defp query_responses(query, read_model, domain) do
    row = JsonSchema.object(read_model.fields, domain, erased: true)

    {key, answer} =
      if query.returns == :one,
        do: {"row", %{"anyOf" => [row, %{"type" => "null"}]}},
        else: {"rows", %{"type" => "array", "items" => row}}

    response = %{
      "type" => "object",
      "properties" => %{key => answer},
      "required" => [key],
      "additionalProperties" => false
    }

    %{
      "200" => %{"description" => "Query answered", "content" => json(response)},
      "401" => %{"description" => "No verified actor"},
      "403" => %{"description" => "Capability or scope refused"},
      "404" => %{"description" => "Capability not found"},
      "422" => %{"description" => "Invalid query parameters"}
    }
  end

  defp receipt_schema do
    event = %{
      "type" => "object",
      "properties" => %{
        "type" => %{"type" => "string"},
        "position" => %{"type" => "integer"}
      },
      "required" => ["position", "type"],
      "additionalProperties" => false
    }

    %{
      "type" => "object",
      "properties" => %{
        "command_id" => %{"type" => "string"},
        "identity" => %{"type" => "object", "additionalProperties" => %{"type" => "string"}},
        "positions" => %{"type" => "array", "items" => %{"type" => "integer"}},
        "position" => %{"anyOf" => [%{"type" => "integer"}, %{"type" => "null"}]},
        "duplicate" => %{"type" => "boolean"},
        "events" => %{"type" => "array", "items" => event}
      },
      "required" => ["command_id", "duplicate", "events", "identity", "position", "positions"],
      "additionalProperties" => false
    }
  end

  defp json(schema), do: %{"application/json" => %{"schema" => schema}}
end
