defmodule DHTGenServer do
  use GenServer

  def start_link(ring_names),
    do: GenServer.start_link(__MODULE__, ring_names, name: __MODULE__)

  def init([]), do: init([:default])
  def init(ring_names) do
    ring = ConsistentHash.ring_for_nodes([node()])
    fun = fn(name, map) -> Map.put(map, name, ring) end
    {:ok, Enum.reduce(ring_names, Map.new(), fun)}
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
    {:noreply, Map.updatet!(rings, ring_name, fn(_) -> ring end)}
  end
end
