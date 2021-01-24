defmodule Cizen.Dispatcher do
  @moduledoc """
  The dispatcher.
  """

  alias Cizen.Dispatcher.{Intake, Node}
  alias Cizen.Event
  alias Cizen.EventType
  alias Cizen.Filter
  alias Cizen.Saga

  require Filter

  @doc false
  def start_link do
    Node.initialize()

    children = [
      %{id: Intake, start: {Intake, :start_link, []}},
      %{
        id: __MODULE__.Registry,
        start: {Registry, :start_link, [[keys: :duplicate, name: __MODULE__]]}
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_all)
  end

  @doc """
  Dispatch the event.
  """
  @spec dispatch(Event.t()) :: :ok
  def dispatch(event) do
    Intake.push(event)
  end

  @doc """
  Listen all events.
  """
  @spec listen_all :: :ok
  def listen_all do
    listen(Filter.new(fn _ -> true end))
  end

  @doc """
  Listen the specific event type.
  """
  @spec listen_event_type(EventType.t()) :: :ok
  def listen_event_type(event_type) do
    listen(Filter.new(fn event -> event.body.__struct__ == event_type end))
  end

  @doc """
  Listen events with the given event filter.
  """
  def listen(event_filter) do
    listen_with_pid(self(), event_filter.code)
  end

  @doc """
  Listen events with the given event filter for the given saga ID.
  """
  def listen(subscriber, event_filter) do
    case Saga.get_pid(subscriber) do
      {:ok, pid} ->
        listen_with_pid(pid, event_filter.code)

      _ ->
        :ok
    end
  end

  defp listen_with_pid(pid, code) do
    Node.put(code, pid)
  end
end
