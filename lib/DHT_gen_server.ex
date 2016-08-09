defmodule DHTGenServer do
  use GenServer

  def start_link(ring_names),
    do: GenServer.start_link(__MODULE__, ring_names, name: __MODULE__)

  def init(ring_names) do
    ring = ConsistentHash.ring_for_nodes([node()])
    fun = fn(name, map) -> Map.put(map, name, ring) end
    {:ok, Enum.reduce(ring_names, Map.new(), fun)}
  end

  def add_rings(ring_names),
    do: GenServer.cast(__MODULE__, {:add_rings, ring_names})

  # no remove_rings as it would wrac havoc if we were removing a ring that still
  # actively used by Supervisorring...

  def get_ring(ring_name),
    do: GenServer.call(__MODULE__, {:get_ring, ring_name})

  def handle_call({:get_ring, ring_name}, _, rings),
    do: {:reply, Map.get(rings, ring_name), rings}

  def handle_cast({:add_rings, ring_names}, rings) do
    ring = ConsistentHash.ring_for_nodes([node()])
    fun =
      fn(name, map) ->
        case Map.has_key?(map, name) do
          true -> map # do not alter an existing ring
          false ->
            Map.put(map, name, ring)
        end
      end
    {:noreply, Enum.reduce(ring_names, rings, fun)}
  end
  def handle_cast({:new_ring, reason, ring_name, new_up_set}, rings) do
    ring = ConsistentHash.ring_for_nodes(new_up_set)
    rings = Map.update!(rings, ring_name, fn(_) -> ring end)
    GenEvent.notify(Supervisorring.Events, {:new_ring, ring_name, reason})
    {:noreply, rings}
  end
end
