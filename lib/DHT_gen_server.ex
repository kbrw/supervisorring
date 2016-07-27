defmodule DHTGenServer do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, ConsistentHash.ring_for_nodes([node])}
  end

  def handle_call(:get_ring, ring), do: {:ok, ring, ring}

  def handle_cast({:new_ring, new_up_set}, _) do
    GenEvent.notify(Supervisorring.Events, :new_ring)
    {:noreply, ConsistentHash.ring_for_nodes(new_up_set)}
  end
end
