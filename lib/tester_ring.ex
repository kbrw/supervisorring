#TODO: move this file to test where it should be

defmodule TesterRing do
  use GenServerring
  require Crdtex
  require Crdtex.Counter

  def init([]), do: {:ok, Crdtex.Counter.new}

  def handle_info(msg, counter) do
    IO.puts("got this weird message #{msg}")
    {:noreply, counter}
  end

  def handle_state_change(state) do
    IO.puts("new state #{Crdtex.value(state)}")
  end

  def handle_ring_change({nodes, reason}),
    do: GenServer.cast(DHTGenServer, {:new_ring, reason, nodes})
end
