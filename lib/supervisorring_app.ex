defmodule Supervisorring.Events do
  def child_spec(_) do Registry.child_spec(keys: :duplicate, name: __MODULE__) end

  @dispatch_key :events
  def dispatch(ev) do
    Registry.dispatch(__MODULE__, @dispatch_key, fn entries ->
      for {pid, nil} <- entries, do: send(pid,{:supervisorring_event,ev})
    end)
  end
  def register do
    {:ok, _} = Registry.register(__MODULE__,@dispatch_key,nil)
  end
end

defmodule Supervisorring.App do
  use Application
  def start(_type,_args) do
    Supervisor.start_link(Supervisorring.App.Sup,[])
  end
  defmodule Sup do
    use Supervisor
    def init([]) do
      Supervisor.init([
        Supervisorring.Events,
        Sup.SuperSup
      ], strategy: :one_for_one)
    end
    defmodule SuperSup do
      defmodule NodesListener do
        use GenServer
        def start_link(init_ring) do GenServer.start_link(__MODULE__, init_ring, name: __MODULE__) end
        def init(init_ring) do
          NanoRing.Events.register
          {:ok,init_ring}
        end
        def handle_info({:node_event,{:new_up_set,_,nodes}},_) do
          Supervisorring.Events.dispatch(:new_ring)
          {:noreply,ConsistentHash.ring_for_nodes(nodes)}
        end
        def handle_info({:node_event,{:new_node_set,_,_}},state), do: {:ok,state}
        def handle_call(:get_ring,_,ring), do: {:reply,ring,ring}
      end
      use GenServer
      def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
      def init(nil) do
        NodesListener.start_link(ConsistentHash.ring_for_nodes(GenServer.call(NanoRing,:get_up)))
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
        GenServer.call(NanoRing,:get_up) |> Enum.filter(&(&1!=node())) |> Enum.each(fn n ->
          GenServer.cast({__MODULE__,n},{:terminate,global_sup_ref})
        end)
        {:noreply,nil}
      end
    end
  end
end
