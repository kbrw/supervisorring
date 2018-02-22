defmodule Supervisorring.NodesListener do
  @moduledoc """
  Handle nodes events
  """
  @behaviour :gen_event

  ###
  ### GenEvent callbacks
  ###
  @doc false
  def init(_), do: {:ok, :ok}

  @doc false
  def handle_call(:get_ring, ring), do: {:ok, ring, ring}

  @doc false
  def handle_event({:new_up_set, _, nodes}, _) do
    :gen_event.notify(Supervisorring.Events, :new_ring)
    {:ok, ConsistentHash.new(nodes)}
  end
  def handle_event({:new_node_set, _, _}, state), do: {:ok, state}

  @doc false
  def handle_info(_info, s), do: {:ok, s}

  @doc false
  def terminate(_, _s), do: :ok
end
