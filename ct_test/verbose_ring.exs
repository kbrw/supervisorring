defmodule TesterRing do # GenServerring callback
  use GenServerring
  require Crdtex
  require Crdtex.Counter

  def init([]), do: {:ok, Crdtex.Counter.new}
  def handle_state_change(_), do: :ok
  def handle_ring_change({nodes, ring_name, reason}) do
    :ct.log(:info, 75, '~p ~p', [nodes, reason], [])
    GenServer.cast(DHTGenServer, {:new_ring, reason, ring_name, nodes})
  end
end
