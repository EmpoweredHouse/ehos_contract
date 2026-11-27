defmodule QueryRig.Domain do
  @moduledoc """
  **Invented**, like the rest of `QueryRig`: a value of every shape a query's param can
  take, so that a test can send each through the query string the OpenAPI document
  describes (#618).
  """

  use EhosContract.Domain, name: :query_rig, language: :en

  context :desk, "Desk", subdomain: :core

  actor :clerk, :human, "Clerk"

  value :minutes, :integer
  value :room_id, :id
  value :tags, {:list, :string}

  value :window do
    field :from, :date
    field :to, :date
  end

  value :need do
    field :service_id, :id
    field :minutes, :minutes
    field :urgent, :boolean
    field :note, :string, optional: true
  end

  value :need_ref, :need

  subdomain :core, "Core", type: :core
end
