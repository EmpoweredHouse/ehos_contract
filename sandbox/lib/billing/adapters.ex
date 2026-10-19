defmodule Billing.Adapters do
  @moduledoc "**Invented.** Adapters for the external systems billing depends on."
  use Boundary, deps: [], exports: [PaymentGateway, PaymentGateway.Fake]
end

defmodule Billing.Adapters.PaymentGateway do
  @moduledoc """
  **Invented.** The payment gateway behind a behaviour. The implementation is chosen by
  configuration, `config :eh_os_contract_host, Billing.Adapters.PaymentGateway, impl:
  ...`, and is the fake unless one is named.
  """

  @callback charge(subscription_id :: String.t(), amount :: non_neg_integer(), key :: String.t()) ::
              {:ok, %{charge_id: String.t()}} | {:error, :unavailable}

  @doc """
  Charges a subscription's customer `amount` cents. The gateway charges once per `key`:
  a second call with the key answers the first charge, as a payment gateway's
  idempotency key does.
  """
  @spec charge(String.t(), non_neg_integer(), String.t()) :: {:ok, map()} | {:error, :unavailable}
  def charge(subscription_id, amount, key), do: impl().charge(subscription_id, amount, key)

  defp impl,
    do: Application.get_env(:eh_os_contract_host, __MODULE__, [])[:impl] || __MODULE__.Fake
end

defmodule Billing.Adapters.PaymentGateway.Fake do
  @moduledoc """
  **Invented.** A fake gateway, not a mock: it implements the behaviour. It takes every
  charge unless told otherwise, by `config :eh_os_contract_host,
  Billing.Adapters.PaymentGateway.Fake, down: ...`: `:always` answers every charge
  `{:error, :unavailable}`, and a number answers that many charges so, then takes them
  again. A gateway being down is not a refused payment: it is an outage, and the
  payment is tried again. A charge's id is its key, so a charge made twice under one key
  is the same charge.
  """

  @behaviour Billing.Adapters.PaymentGateway

  @impl true
  def charge(_subscription_id, _amount, key) do
    case Application.get_env(:eh_os_contract_host, __MODULE__, [])[:down] do
      :always ->
        {:error, :unavailable}

      calls when is_integer(calls) and calls > 0 ->
        Application.put_env(:eh_os_contract_host, __MODULE__, down: calls - 1)
        {:error, :unavailable}

      _up ->
        {:ok, %{charge_id: "charge-#{key}"}}
    end
  end
end
