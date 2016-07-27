defmodule DHTGenServer do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init([]), do: {:ok, ConsistentHash.ring_for_nodes([node])}

  def handle_call(:get_ring, _, ring), do: {:reply, ring, ring}

  def handle_cast({:new_ring, new_up_set}, _) do
    GenEvent.notify(Supervisorring.Events, :new_ring)
    {:noreply, ConsistentHash.ring_for_nodes(new_up_set)}
  end
end
