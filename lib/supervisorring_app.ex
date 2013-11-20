defmodule Supervisorring.App do
  use Application.Behaviour
  def start(_type,_args) do
    :supervisor.start_link(Supervisorring.App.Sup,[])
  end
  defmodule Sup do
    use Supervisor.Behaviour
    def init([]) do
      supervise([
        worker(:gen_event,[{:local,Supervisorring.Events}], id: Supervisorring.Events),
        worker(Sup.SuperSup,[])
      ], strategy: :one_for_one)
    end
    defmodule SuperSup do
      def init(nil) do
        Process.flag(:trap_exit,true)
        {:ok,nil}
      end
      defmodule NodesListener do
        def handle_event({:new_ring,oldring,newring},state) do
          case {oldring.up_set|>to_list,newring.up_set|>to_list} do
            {unchange,unchange}-> {:ok,state}
            {_,newnodes} -> :gen_event.notify(Supervisorring.Events,:new_ring)
              {:ok,ConsistentHash.ring_for_nodes(newnodes)}
          end
        end
        def handle_call(:get_ring,ring), do: {:ok,ring,ring}
      end
      use GenServer.Behaviour
      def init(args) do
        :gen_event.add_sup_handler(NanoRing.Events,NodesListener,
          ConsistentHash.ring_for_nodes(:gen_server.call(NanoRing,:get_up)))
      end
      def handle_cast({:terminate,global_sup},state), do: exit(global_sup,:normal)
      def handle_info({'EXIT',from,reason},state) when reason != :normal do
        :gen_server.call(NanoRing,:get_up) |> Enum.each fn n ->
          :gen_server.cast({n,__MODULE__},{:terminate,from|>Process.info(:registered_name)})
        end
      end
      def handle_info({:gen_event_EXIT,_,_},s), do: exit(:ring_listener_died)
    end
  end
end


