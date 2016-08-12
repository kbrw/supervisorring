# a small helper that put in place the needed communication between
# GenServerring and Supervisorring. If you do not want to use it, remember that
# your ring callback has to implement handle_ring_change. However you're
# strongly advised to use this wrapper

defmodule GenServerring.Supervisorring.Link do
  defmacro __using__(_) do
    quote do
      use GenServerring
      def handle_ring_change({nodes, ring_name, reason}),
        do: GenServer.cast(DHTGenServer, {:new_ring, reason, ring_name, nodes})
    end
  end
end
