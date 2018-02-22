defmodule Supervisorring.NodesListener do
  @moduledoc """
  Handle nodes eventsx
  """
  use GenEvent

  ###
  ### GenEvent callbacks
  ###
  @doc false
  def handle_event({:new_up_set, _, nodes}, _) do
    :gen_event.notify(Supervisorring.Events, :new_ring)
    {:ok, ConsistentHash.new(nodes)}
  end
  def handle_event({:new_node_set, _, _}, state), do: {:ok, state}

  @doc false
  def handle_call(:get_ring, ring), do: {:ok, ring, ring}
end
