defmodule Supervisorring.App do
  use Application

  def start(_type, _) do
    ring_name = Application.fetch_env!(:supervisorring, :gen_serverring_name)
    Supervisor.start_link(Supervisorring.App.Sup, [ring_name])
  end

  defmodule Sup do
    use Supervisor

    def init(ring_name) do
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

      def ring_name(), do: GenServer.call(__MODULE__, :ring_name)

      def init(ring_name), do: {:ok, ring_name}

      def handle_call(:ring_name, _, state), do: {:reply, state, state}
      def handle_cast({:monitor, global_sup_ref}, state) do
        Process.monitor(global_sup_ref)
        {:noreply, state}
      end
      def handle_cast({:terminate, global_sup_ref}, state) do
        true = Process.exit(Process.whereis(global_sup_ref), :kill)
        {:noreply, state}
      end

      def handle_info({:DOWN, _, :process, _, :killed}, state),
        do: {:noreply, state}
      def handle_info({:DOWN, _, :process, {global_sup_ref, _}, _}, state) do
        stop_fun =
          fn n ->
            GenServer.cast({__MODULE__, n}, {:terminate, global_sup_ref})
          end
        GenServer.call(state, :get_up)
        |> Enum.filter(&(&1 != node))
        |> Enum.each(stop_fun)
        {:noreply, state}
      end
      def handle_info({:gen_event_EXIT, _, _}, _state),
        do: exit(:ring_listener_died)

    end
  end
end
