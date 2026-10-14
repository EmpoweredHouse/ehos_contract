defmodule GraphLab.PatientMessaging.SendSms do
  @moduledoc """
  Sends a queued message through the SMS gateway and records its delivery report as
  the integration, in the test set (`GraphLab`).

  **There is no gateway behind the sandbox**, so the send is the gateway saying
  delivered, unless the application environment says it is down:
  `config :eh_os_contract_host, GraphLab.PatientMessaging.SendSms, gateway: :down`, which
  nothing configures and only `mix graph_lab.traffic` sets for a while, to leave a send
  that failed until Oban gave up on it. The event's identifier keys the recording, so a
  second delivery records nothing new.
  """

  use GraphLab.Contracts.PatientMessaging, effect: :send_sms

  alias EhOsContract.Actor
  alias GraphLab.Contracts.PatientMessaging.Events.MessageDelivered

  @impl true
  def message_queued(%MessageQueued{visit_id: id, kind: kind, __meta__: meta}) do
    with :up <- gateway(),
         {:ok, _receipt} <-
           EhOsContract.record(
             GraphLab.Contracts.PatientMessaging,
             %MessageDelivered{visit_id: id, kind: kind},
             actor: Actor.system(:sms_integration),
             idempotency_key: "message-delivered:#{meta.id}",
             causation_id: meta.id,
             correlation_id: meta.correlation_id
           ) do
      :ok
    else
      :down -> {:error, :gateway_down}
      error -> error
    end
  end

  defp gateway do
    :eh_os_contract_host
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:gateway, :up)
  end
end
