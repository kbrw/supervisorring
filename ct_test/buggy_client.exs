defmodule GenericServer do # Supervisorringed client...
  use GenServer
  def start_link(_), do: {:ok, nil}
  def handle_call(:get, _, s), do: {:reply, s, s}
  # next cast is forcing the client to fail
  def handle_cast(:berzek, s) do
    :ct.log(:info, 75, 'Going berzek ~p', [self()], [])
    _ = 1 + s
    {:noreply, s}
  end
  def handle_cast(new_state, _), do: {:noreply, new_state}
end
