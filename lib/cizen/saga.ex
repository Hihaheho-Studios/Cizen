defmodule Cizen.Saga do
  @moduledoc """
  The saga behaviour

  ## Example

      defmodule SomeSaga do
        use Cizen.Saga
        defstruct []

        @impl true
        def init(_id, %__MODULE__{}) do
          saga
        end

        @impl true
        def handle_event(_id, _event, state) do
          state
        end
      end
  """

  @type t :: struct

  use GenServer

  alias Cizen.CizenSagaRegistry
  alias Cizen.Dispatcher
  alias Cizen.Event
  alias Cizen.SagaID

  @type state :: any

  @doc """
  Invoked when the saga is started.
  Saga.Started event will be dispatched after this callback.

  Returned value will be used as the next state to pass `c:handle_event/3` callback.
  """
  @callback init(SagaID.t(), t()) :: state

  @doc """
  Invoked when the saga receives an event.

  Returned value will be used as the next state to pass `c:handle_event/3` callback.
  """
  @callback handle_event(SagaID.t(), Event.t(), state) :: state

  @doc """
  Invoked when the saga is resumed.

  Returned value will be used as the next state to pass `c:handle_event/3` callback.

  This callback is predefined. The default implementation is here:
  ```
  def resume(id, saga, state) do
    init(id, saga)
    state
  end
  ```
  """
  @callback resume(SagaID.t(), t(), state) :: state

  defmacro __using__(_opts) do
    quote do
      @behaviour Cizen.Saga

      @impl true
      def resume(id, saga, state) do
        init(id, saga)
        state
      end

      defoverridable resume: 3
    end
  end

  defmodule Finish do
    @moduledoc "A event fired to finish"
    defstruct([:id])
  end

  defmodule Started do
    @moduledoc "A event fired on start"
    defstruct([:id])
  end

  defmodule Ended do
    @moduledoc "A event fired on end"
    defstruct([:id])
  end

  defmodule Finished do
    @moduledoc "A event fired on finish"
    defstruct([:id])
  end

  defmodule Crashed do
    @moduledoc "A event fired on crash"
    defstruct([:id, :reason, :stacktrace])
  end

  @doc """
  Starts a saga which finishes when the current process exits.
  """
  @spec fork(t) :: SagaID.t()
  def fork(saga) do
    lifetime = self()
    id = SagaID.new()

    {:ok, _pid} = GenServer.start_link(__MODULE__, {:start, id, saga, lifetime})

    id
  end

  @doc """
  Starts a saga linked to the current process
  """
  @spec start_link(t) :: GenServer.on_start()
  def start_link(saga) do
    id = SagaID.new()
    GenServer.start_link(__MODULE__, {:start, id, saga, nil})
  end

  @doc """
  Returns the pid for the given saga ID.
  """
  @spec get_pid(SagaID.t()) :: {:ok, pid} | :error
  defdelegate get_pid(saga_id), to: CizenSagaRegistry

  @doc """
  Returns the saga struct for the given saga ID.
  """
  @spec get_saga(SagaID.t()) :: {:ok, t()} | :error
  defdelegate get_saga(saga_id), to: CizenSagaRegistry

  @lazy_launch {__MODULE__, :lazy_launch}

  def lazy_launch, do: @lazy_launch

  @doc """
  Returns the module for a saga.
  """
  @spec module(t) :: module
  def module(saga) do
    saga.__struct__
  end

  @doc """
  Resumes a saga with the given state.
  """
  @spec resume(SagaID.t(), t(), state) :: GenServer.on_start()
  def resume(id, saga, state) do
    GenServer.start(__MODULE__, {:resume, id, saga, state})
  end

  def start_saga(id, saga, lifetime) do
    {:ok, _pid} = GenServer.start(__MODULE__, {:start, id, saga, lifetime})
  end

  def end_saga(id) do
    GenServer.stop({:via, Registry, {CizenSagaRegistry, id}}, :shutdown)
  catch
    :exit, _ -> :ok
  after
    Dispatcher.dispatch(Event.new(nil, %Ended{id: id}))
  end

  def send_to(id, message) do
    Registry.dispatch(CizenSagaRegistry, id, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end

  def exit(id, reason, trace) do
    GenServer.stop({:via, Registry, {CizenSagaRegistry, id}}, {:shutdown, {reason, trace}})
  end

  @impl true
  def init({type, id, saga, lifetime_or_state}) do
    Registry.register(CizenSagaRegistry, id, saga)
    Dispatcher.listen_event_body(%Finish{id: id})
    module = module(saga)

    state = init_on(type, id, module, saga, lifetime_or_state)

    {:ok, {id, module, state}}
  end

  defp init_on(:start, id, module, saga, lifetime) do
    unless is_nil(lifetime), do: Process.monitor(lifetime)

    case module.init(id, saga) do
      {@lazy_launch, state} ->
        state

      state ->
        Dispatcher.dispatch(Event.new(id, %Started{id: id}))
        state
    end
  end

  defp init_on(:resume, id, module, saga, state) do
    module.resume(id, saga, state)
  end

  @impl true
  def handle_info(%Event{body: %Finish{id: id}}, {id, module, state}) do
    {:stop, {:shutdown, :finish}, {id, module, state}}
  end

  @impl true
  def handle_info(%Event{} = event, {id, module, state}) do
    state = module.handle_event(id, event, state)
    {:noreply, {id, module, state}}
  rescue
    reason -> {:stop, {:shutdown, {reason, __STACKTRACE__}}, {id, module, state}}
  end

  @impl true
  def handle_info({:DOWN, _, :process, _, _}, state) do
    {:stop, {:shutdown, :finish}, state}
  end

  @impl true
  def terminate(:shutdown, {_id, _module, _state}) do
    :shutdown
  end

  def terminate({:shutdown, :finish}, {id, _module, _state}) do
    Dispatcher.dispatch(Event.new(id, %Finished{id: id}))
    :shutdown
  end

  def terminate({:shutdown, {reason, trace}}, {id, _module, _state}) do
    Dispatcher.dispatch(Event.new(id, %Crashed{id: id, reason: reason, stacktrace: trace}))

    :shutdown
  end

  @impl true
  def handle_call(:get_saga_id, _from, state) do
    [saga_id] = Registry.keys(CizenSagaRegistry, self())
    {:reply, saga_id, state}
  end

  def handle_call(request, _from, state) do
    result = handle_request(request)
    {:reply, result, state}
  end

  @doc false
  def handle_request({:register, registry, saga_id, key, value}) do
    Registry.register(registry, key, {saga_id, value})
  end

  def handle_request({:unregister, registry, key}) do
    Registry.unregister(registry, key)
  end

  def handle_request({:unregister_match, registry, key, pattern, guards}) do
    Registry.unregister_match(registry, key, pattern, guards)
  end

  def handle_request({:update_value, registry, key, callback}) do
    Registry.update_value(registry, key, fn {saga_id, value} -> {saga_id, callback.(value)} end)
  end
end
