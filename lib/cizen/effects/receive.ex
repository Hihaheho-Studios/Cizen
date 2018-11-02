defmodule Cizen.Effects.Receive do
  @moduledoc """
  An effect to receive an event which the saga is received.

  Returns the received event.

  If the `event_filter` is omitted, this receives all events.

  ## Example
      perform id, %Subscribe{
        event_filter: Filter.new(fn %Event{body: %SomeEvent{}} -> true end)
      }

      perform id, %Receive{
        event_filter: Filter.new(fn %Event{body: %SomeEvent{}} -> true end)
      }
  """

  alias Cizen.Effect
  alias Cizen.Event
  alias Cizen.Filter
  alias Cizen.Request.Response

  defstruct event_filter: %Filter{}

  use Effect

  @impl true
  def init(_handler, %__MODULE__{}) do
    :ok
  end

  @impl true
  def handle_event(_handler, %Event{body: %Response{}}, _, state), do: state

  def handle_event(_handler, event, effect, state) do
    if Filter.match?(effect.event_filter, event) do
      {:resolve, event}
    else
      state
    end
  end
end
