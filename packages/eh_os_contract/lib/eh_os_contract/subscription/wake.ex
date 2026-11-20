defmodule EhOsContract.Subscription.Wake do
  # Sends the engine's own wake to the runners after a transaction the engine owns
  # commits (`EhOsContract.Subscription.Runner.notify/0`), one process per node (#648).
  #
  # Where the log's trigger (storage version 6, #649) reaches this node's runners, it
  # has already woken them at that commit, so this process sends nothing: a second wake
  # would only make each runner step again and find nothing. The trigger reaches them
  # when Oban runs its Postgres notifier with the log's schema as its prefix, which the
  # engine's supervisor checks at boot and passes as `trigger:`. Elsewhere — another
  # prefix, `Oban.Notifiers.PG` — this process notifies through Oban, as the engine did
  # before. A node without this process (`subscriptions: :manual`, or no subscription)
  # notifies from the caller, as before.
  @moduledoc false

  use GenServer

  @name __MODULE__

  @typedoc false
  @type state :: %{trigger: boolean()}

  @doc false
  @spec name() :: atom()
  def name, do: @name

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc """
  Whether the log's trigger wakes the runners of a node whose Oban runs `notifier`
  with `prefix`, for a log in `schema`.
  """
  @spec reaches?(module(), String.t() | false | nil, String.t()) :: boolean()
  def reaches?(Oban.Notifiers.Postgres, schema, schema) when is_binary(schema), do: true
  def reaches?(_notifier, _prefix, _schema), do: false

  @doc "Takes `trigger:` (a boolean, required) and `name:`."
  @impl GenServer
  @spec init(keyword()) :: {:ok, state()}
  def init(opts), do: {:ok, %{trigger: Keyword.fetch!(opts, :trigger)}}

  @doc "Sends the wake through Oban unless the trigger already sent it."
  @impl GenServer
  @spec handle_cast(:notify, state()) :: {:noreply, state()}
  def handle_cast(:notify, %{trigger: true} = state), do: {:noreply, state}

  def handle_cast(:notify, state) do
    EhOsContract.Subscription.Runner.notify_through_oban()
    {:noreply, state}
  end
end
