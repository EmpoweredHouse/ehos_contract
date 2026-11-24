defmodule EhosContract.Subscription.Wake do
  # Says, by running, that the log's trigger (storage version 6, #649) wakes this node's
  # runners at commit, so the engine sends no wake of its own after a transaction it
  # owns (`EhosContract.Subscription.Runner.notify/0`, #648): a second wake would only
  # make each runner step again and find nothing.
  #
  # The engine's supervisor decides at boot and passes the answer as `trigger:`. With
  # `trigger: false` the process does not start (`:ignore`), and the caller notifies
  # through Oban after its commit, as the engine did before: one query in each
  # committing process, so a slow database slows the caller and not a queue. So does a
  # node without the child at all (`subscriptions: :manual`, no subscription), which
  # keeps a test from seeing another's setting.
  #
  # The trigger reaches the runners when Oban runs on the engine's repo, with its
  # Postgres notifier and the log's schema as its prefix: the trigger notifies
  # `"<schema>.oban_ehos_contract"` in the log's database, and that is where and what
  # Oban then listens on.
  @moduledoc false

  use GenServer

  @name __MODULE__

  @doc false
  @spec name() :: atom()
  def name, do: @name

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc """
  Whether the log's trigger wakes the runners of a node whose Oban is configured as
  `oban` (its `notifier`, `prefix` and `repo`), for a log in `schema` of `repo`.
  """
  @spec reaches?(map(), module(), String.t()) :: boolean()
  def reaches?(
        %{notifier: {Oban.Notifiers.Postgres, _}, prefix: schema, repo: repo},
        repo,
        schema
      )
      when is_binary(schema),
      do: true

  def reaches?(_oban, _repo, _schema), do: false

  @doc "Starts only with `trigger: true`; `trigger: false` is `:ignore`."
  @impl GenServer
  @spec init(keyword()) :: {:ok, nil} | :ignore
  def init(opts) do
    if Keyword.fetch!(opts, :trigger), do: {:ok, nil}, else: :ignore
  end
end
