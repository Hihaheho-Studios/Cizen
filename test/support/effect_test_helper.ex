defmodule Citadel.EffectTestHelper do
  @moduledoc false

  defmodule TestEvent do
    @moduledoc false
    defstruct [:value]
  end

  defmodule TestEffect do
    @moduledoc false
    defstruct [:value, :resolve_immediately, :alias_of]

    alias Citadel.Automaton.Effect
    @behaviour Effect

    @impl true
    def init(_handler, effect) do
      if is_nil(effect.alias_of) do
        if effect.resolve_immediately do
          {:resolve, effect.value}
        else
          effect.value
        end
      else
        {:alias_of, effect.alias_of}
      end
    end

    @impl true
    def handle_event(_handler, event, %__MODULE__{value: value}, value) do
      if event.body.value == :ignored do
        value
      else
        if value == event.body.value do
          {:resolve, value}
        else
          {:consume, value}
        end
      end
    end
  end
end
