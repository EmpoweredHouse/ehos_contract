defmodule EhOsContract.Auth.Mail.Result do
  @moduledoc """
  What one recipient of `EhOsContract.Auth.Mail.deliver/1` came to.

    * `to`: the recipient, as given;
    * `sent?`: whether the company's relay took the message. Taken is not delivered;
    * `message_id`: the message's `Message-ID`, also when it was not sent;
    * `relay_response`: the relay's last answer as it wrote it, which names its queue id
      in its own words, or nil where it said nothing;
    * `reason`: why the message was not sent, EHOS's sentence, or nil when it was.
      The other recipients were still tried; trying this one again is the application's
      choice.
  """

  @enforce_keys [:to, :sent?, :message_id]
  defstruct [:to, :sent?, :message_id, relay_response: nil, reason: nil]

  @type t :: %__MODULE__{
          to: EhOsContract.Auth.Mail.recipient(),
          sent?: boolean(),
          message_id: String.t(),
          relay_response: String.t() | nil,
          reason: String.t() | nil
        }

  @doc false
  # As EHOS's mail API writes one, or `:error` for anything else.
  @spec from_map(term()) :: {:ok, t()} | :error
  def from_map(%{"to" => to, "sent" => sent, "message_id" => message_id} = map)
      when is_boolean(sent) and is_binary(message_id) do
    with {:ok, to} <- to(to),
         relay when is_nil(relay) or is_binary(relay) <- map["relay_response"],
         reason when is_nil(reason) or is_binary(reason) <- map["reason"] do
      {:ok,
       %__MODULE__{
         to: to,
         sent?: sent,
         message_id: message_id,
         relay_response: relay,
         reason: reason
       }}
    else
      _other -> :error
    end
  end

  def from_map(_other), do: :error

  defp to(%{"person" => id}) when is_binary(id), do: {:ok, {:person, id}}
  defp to(%{"address" => address}) when is_binary(address), do: {:ok, {:address, address}}
  defp to(_other), do: :error
end
