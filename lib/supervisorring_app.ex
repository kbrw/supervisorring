defmodule Supervisorring.App do
  use Application

  def start(_type,_args) do
    Supervisor.start_link(Supervisorring.App.Sup,[])
  end

  defmodule Sup do
    use Supervisor

    def init([]) do
      name = Supervisorring.Events
      children =
        [worker(:gen_event, [{:local, name}], id: name),
         worker(Sup.SuperSup, ring_name),
         worker(DHTGenServer, [nil])]
      supervise(children, strategy: :one_for_one)
    end

    defmodule SuperSup do
      use GenServer

      def start_link(ring_name),
        do: GenServer.start_link(__MODULE__, ring_name, name: __MODULE__)

        def handle_event({:new_up_set, _, nodes}, _) do
            :gen_event.notify(Supervisorring.Events, :new_ring)
            {:ok, ConsistentHash.ring_for_nodes(nodes)}
        end
        def handle_event({:new_node_set, _, _}, state), do: {:ok, state}

      def handle_cast({:monitor, global_sup_ref}, state) do
        Process.monitor(global_sup_ref)
        {:noreply, nil}
      end
      def handle_cast({:terminate, global_sup_ref}, nil) do
        true = Process.exit(Process.whereis(global_sup_ref), :kill)
        {:noreply, nil}
      end

      def handle_info({:DOWN, _, :process, _, :killed}, nil) do
        {:noreply, nil}
      end
      def handle_info({:DOWN, _, :process, {global_sup_ref, _}, _}, nil) do
        init_fun =
          fn n ->
            GenServer.cast({__MODULE__,n}, {:terminate, global_sup_ref})
          end
        # here also, we need the name of the GenServerring
        GenServer.call(GenServerring, :get_up)
          |> Enum.filter(&(&1 != node))
          |> Enum.each init_fun.
        {:noreply, nil}
      end
      def handle_info({:gen_event_EXIT, _, _}, nil)
        do exit(:ring_listener_died)
      end

    end
  end
end
