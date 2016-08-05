defmodule DHTGenServer do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init([]) do
    ring = ConsistentHash.ring_for_nodes([node()])
    {:ok, Map.put(Map.new(), :default, ring)}
  end

  def get_ring(ring_name \\ :default),
    do: GenServer.call(__MODULE__, {:get_ring, ring_name})

  def handle_call({:get_ring, ring_name}, _, rings),
    do: {:reply, Map.get(rings, ring_name), rings}

  def handle_cast({:new_ring, reason, new_up_set}, rings),
    do: handle_cast({:new_ring, reason, new_up_set, :default}, rings)
  def handle_cast({:new_ring, reason, new_up_set, ring_name}, rings) do
    ring = ConsistentHash.ring_for_nodes(new_up_set)
    GenEvent.notify(Supervisorring.Events, {:new_ring, reason})
    {:noreply, Map.put(rings, ring_name, ring)}
  end
end
