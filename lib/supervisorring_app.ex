defmodule Supervisorring.App do
  use Application

  def start(_type, ring_names),
    do: Supervisor.start_link(Supervisorring.App.Sup, ring_names)

  defmodule Sup do
    use Supervisor

    def init(ring_names) do
      name = Supervisorring.Events
      children =
        [worker(:gen_event, [{:local, name}], id: name),
         # the ring_name should be kept at ChildManager Level
         worker(Sup.SuperSup, [nil]),
         worker(DHTGenServer, [ring_names])]
      supervise(children, strategy: :one_for_one)
    end

    defmodule SuperSup do
      use GenServer

      def start_link(_),
        do: GenServer.start_link(__MODULE__, Map.new(), name: __MODULE__)

      def init(state), do: {:ok, state}

      def handle_cast({:monitor, global_sup_ref, ring_name}, state) do
        Process.monitor(global_sup_ref)
        {:noreply, Map.put(state, global_sup_ref, ring_name)}
      end
      def handle_cast({:terminate, global_sup_ref}, state) do
        case Process.whereis(global_sup_ref) do
          nil -> :nothingtodo
          pid when is_pid(pid) -> true = Process.exit(pid, :kill)
        end
        {:noreply, Map.delete(state, global_sup_ref)}
      end

      def handle_info({:DOWN, _, :process, _, :killed}, state),
        do: {:noreply, state}
      def handle_info({:DOWN, _, :process, {global_sup_ref, _}, _}, state) do
        stop_fun =
          fn n ->
            GenServer.cast({__MODULE__, n}, {:terminate, global_sup_ref})
          end
        {:ok, ring_server} = Map.fetch(state, global_sup_ref)
        GenServer.call(ring_server, :get_up)
        |> Enum.filter(&(&1 != node))
        |> Enum.each(stop_fun)
        {:noreply, Map.delete(state, global_sup_ref)}
      end
      def handle_info({:gen_event_EXIT, _, _}, _state),
        do: exit(:ring_listener_died)

    end
  end
end
