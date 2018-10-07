defmodule Citadel.Automaton.Effects.Dispatch do
  @moduledoc """
  An effect to dispatch an event.

  Returns the dispatched event.
  """

  defstruct [:body]

  alias Citadel.Automaton.Effect
  alias Citadel.Dispatcher
  alias Citadel.Event

  @behaviour Effect

  @impl true
  def init(_handler, %__MODULE__{body: body}) do
    event = Event.new(body)
    Dispatcher.dispatch(event)
    {:resolve, event}
  end

  @impl true
  def handle_event(_, _, _, _), do: nil
end
