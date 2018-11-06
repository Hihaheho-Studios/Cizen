defmodule Cizen.EffectfulTest do
  use Cizen.SagaCase

  alias Cizen.Dispatcher
  alias Cizen.Event
  alias Cizen.Filter

  alias Cizen.Effects.{Dispatch}

  defmodule(TestEvent, do: defstruct([:value]))

  defmodule TestModule do
    use Cizen.Effectful

    def dispatch(body) do
      handle(fn id ->
        perform(id, %Dispatch{body: body})
      end)
    end

    def block do
      handle(fn _id ->
        # Block
        receive do
          _ -> :ok
        end
      end)
    end

    def return(value) do
      handle(fn _id ->
        value
      end)
    end
  end

  describe "handle/1" do
    test "handles effect" do
      Dispatcher.listen_event_type(TestEvent)

      spawn_link(fn ->
        TestModule.dispatch(%TestEvent{value: :somevalue})
      end)

      assert_receive %Event{body: %TestEvent{value: :somevalue}}
    end

    test "blocks the current thread" do
      spawn_link(fn ->
        TestModule.block()
        flunk("called")
      end)

      :timer.sleep(10)
    end

    test "returns the last expression" do
      task =
        Task.async(fn ->
          TestModule.return(:somevalue)
        end)

      assert :somevalue == Task.await(task)
    end

    test "works with other messages" do
      pid = self()
      filter = Filter.new(fn %Event{body: %TestEvent{value: a}} -> a == 1 end)

      task =
        Task.async(fn ->
          send(
            pid,
            handle(fn id ->
              perform id, %Subscribe{
                event_filter: filter
              }

              send(pid, :subscribed)

              perform id, %Receive{
                event_filter: filter
              }
            end)
          )
        end)

      receive do
        :subscribed -> :ok
      end

      send(task.pid, Event.new(nil, %TestEvent{value: 2}))
      Dispatcher.dispatch(Event.new(nil, %TestEvent{value: 1}))
      assert %Event{body: %TestEvent{value: 1}} = Task.await(task)
    end
  end
end
