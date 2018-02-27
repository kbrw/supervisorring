defmodule NodesTest do
  use ExUnit.Case

  require Logger

  alias Mix.DistEnv

  defmodule TestNodesHandler do
    @behaviour :gen_event

    def init(pid), do: {:ok, pid}

    def handle_call(_, s), do: {:ok, :ok, s}
    
    def handle_event(:node_change, pid) do
      send(pid, :node_change)
      {:ok, pid}
    end

    def handle_info(_, s), do: {:ok, s}

    def terminate(_, _s), do: :ok
  end

  setup do
    if not Node.alive? do
      raise """
      Node is not in distributed mode
      You can launch tests with : `mix test.distributed`
      """
    end
    
    Supervisorring.Nodes.reset()

    :ok = DistEnv.start_slaves(["dev1", "dev2", "dev3"])
    n = DistEnv.nodes() |> Enum.map(&("#{&1}<#{Node.ping(&1)}>")) |> Enum.join(" ")
    IO.puts "### nodes: #{n}"

    on_exit fn ->
      IO.puts "(setup) teardown"
      :ok = DistEnv.stop_slaves()
    end
    :ok
  end
 
  test "Nodes join / leave" do
    assert Supervisorring.Nodes.nodes() |> Enum.count() == 0

    IO.puts "(test1) ALIVE ? #{Node.alive?()}"
    DistEnv.nodes() |>
      Enum.each(fn node -> IO.puts "(test1) PING(#{node}) -> #{Node.ping(node)}" end)
    DistEnv.nodes |> Enum.map(&Supervisorring.Nodes.join/1)
    :timer.sleep(500)

    assert Supervisorring.Nodes.up() |> Enum.count() == 4

    :ok = DistEnv.stop_slave("dev2")
    :timer.sleep(500)
    assert :"dev2@127.0.0.1" not in Supervisorring.Nodes.up()
    assert :"dev2@127.0.0.1" in Supervisorring.Nodes.nodes()

    :ok = DistEnv.start_slaves(["dev2"])
    :timer.sleep(500)
    assert :"dev2@127.0.0.1" in Supervisorring.Nodes.up()
  end

  test "Test events" do
    Supervisorring.Nodes.subscribe(TestNodesHandler, self())

    nodes = DistEnv.nodes()
    n = Enum.count(nodes)
    IO.puts "(test2) ALIVE ? #{Node.alive?()}"
    DistEnv.nodes() |>
      Enum.each(fn node -> IO.puts "(test2) PING(#{node}) -> #{Node.ping(node)}" end)
    DistEnv.nodes() |> Enum.map(&Supervisorring.Nodes.join/1)

    :timer.sleep(500)
    
    for _ <- 1..n do
      assert_receive :node_change, 500
    end
  end
end
