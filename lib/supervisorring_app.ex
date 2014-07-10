defmodule Supervisorring.App do
  use Application
  def start(_type,_args) do
    :supervisor.start_link(Supervisorring.App.Sup,[])
  end
  defmodule Sup do
    use Supervisor
    def init([]) do
      supervise([
        worker(:gen_event,[{:local,Supervisorring.Events}], id: Supervisorring.Events),
        worker(Sup.SuperSup,[])
      ], strategy: :one_for_one)
    end
    defmodule SuperSup do
      defmodule NodesListener do
        use GenEvent
        def handle_event({:new_up_set,_,nodes},_) do
            IO.puts "new cluster : #{inspect nodes}"
            :gen_event.notify(Supervisorring.Events,:new_ring)
            {:ok,ConsistentHash.ring_for_nodes(nodes)}
        end
        def handle_event({:new_node_set,_,_},state), do: {:ok,state}
        def handle_call(:get_ring,ring), do: {:ok,ring,ring}
      end
      use GenServer
      def start_link, do: :gen_server.start_link({:local,__MODULE__},__MODULE__,nil,[])
      def init(nil) do
        :gen_event.add_sup_handler(NanoRing.Events,NodesListener,
          ConsistentHash.ring_for_nodes(:gen_server.call(NanoRing,:get_up)))
        {:ok,nil}
      end
      def handle_cast({:monitor,global_sup_ref},nil) do
        Process.monitor(global_sup_ref)
        {:noreply,nil}
      end
      def handle_cast({:terminate,global_sup_ref},nil) do
        true=Process.exit(Process.whereis(global_sup_ref),:kill)
        {:noreply,nil}
      end
      def handle_info({:DOWN,_,:process,_,:killed},nil), do: {:noreply,nil}
      def handle_info({:DOWN,_,:process,{global_sup_ref,_},_},nil) do
        IO.puts "try to kill all the other supervisor"
        :gen_server.call(NanoRing,:get_up) |> Enum.filter(&(&1!=node)) |> Enum.each fn n ->
          :gen_server.cast({__MODULE__,n},{:terminate,global_sup_ref})
        end
        {:noreply,nil}
      end
      def handle_info({:gen_event_EXIT,_,_},nil), do: exit(:ring_listener_died)
    end
  end
end
