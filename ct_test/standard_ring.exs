defmodule TesterRing do # GenServerring callback
  use GenServerring.Supervisorring.Link
  require Crdtex
  require Crdtex.Counter

  def init([]), do: {:ok, Crdtex.Counter.new}
  def handle_state_change(_), do: :ok
end
