Code.require_file "test_helper.exs", __DIR__

defmodule MyApp do
  use Application

  defmodule SupRing do # stuff common to the 2 supervisor rings

    def migrate({_, _, _}, old, new),
      do: GenServer.cast(new, GenServer.call(old, :get))

    def client_spec(name) do
      {name,
        {:gen_server, :start_link, [{:local, name}, GenericServer, nil, []]},
        :permanent, 2, :worker, [GenericServer]}
    end

    def init(sup_name, ring_name, module) do
      {:ok,
        {{:one_for_one, 2, 3},
          [{:dyn_child_handler, module},
            client_spec(:"#{sup_name}.C1"),
            client_spec(:"#{sup_name}.C2")],
          ring_name}}
    end

    def add(childspec, file) do
      File.write!(
        file,
        File.read!()
        |> :erlang.binary_to_term
        |> List.insert_at(0, childspec)
        |> :erlang.term_to_binary)
    end

    def del(childid, file) do
      File.write!(
        file,
        File.read!(file)
        |> :erlang.binary_to_term
        |> List.keydelete(childid, 0)
        |> :erlang.term_to_binary)
    end
  end # MyApp.SupRing

  defmodule SupRing1 do
    use Supervisorring

    def migrate(a, b, c), do: MyApp.SupRing.migrate(a, b, c)
    def init(_ring_name),
      do: MyApp.SupRing.init(__MODULE__, :test_ring1, __MODULE__)
    @behaviour :dyn_child_handler
    def match(_), do: true
    def get_all, do: "childs_1" |> File.read! |> :erlang.binary_to_term
    def add(childspec), do: MyApp.SupRing.add(childspec, "childs_1")
    def del(childspec), do: MyApp.SupRing.del(childspec, "childs_1")
    def start_link(sup_name) do
      :supervisorring.start_link(sup_name, __MODULE__, :test_ring1)
    end
  end # MyApp.SupRing1

  defmodule SupRing2 do
    use Supervisorring

    def migrate(a, b, c), do: MyApp.SupRing.migrate(a, b, c)
    def init(_ring_name),
      do: MyApp.SupRing.init(__MODULE__, :test_ring2, __MODULE__)
    @behaviour :dyn_child_handler
    def match(_), do: true
    def get_all, do: "childs_2" |> File.read! |> :erlang.binary_to_term
    def add(childspec), do: MyApp.SupRing.add(childspec, "childs_2")
    def del(childspec), do: MyApp.SupRing.del(childspec, "childs_2")
    def start_link(sup_name) do
      :supervisorring.start_link(sup_name, __MODULE__, :test_ring2)
    end
  end # MyApp.SupRing2

  def start(_type, args),
    do: Supervisor.start_link(MyApp.Sup, args)

  defmodule Sup do
    use Supervisor

    def init(_) do
      wrk =
        fn(sup_name) ->
          worker(sup_name, [{:local, sup_name}], id: sup_name)
        end
      children = [wrk.(MyApp.SupRing1), wrk.(MyApp.SupRing2)]
      supervise(children, strategy: :one_for_one)
    end
  end
end

defmodule GenericServer do # Supervisorringed client...
  use GenServer
  def start_link(_), do: {:ok, nil}
  def handle_call(:get, _, s), do: {:reply, s, s}
  def handle_cast(new_state, _), do: {:noreply, new_state}
end

defmodule TesterRing do # GenServerring callback
  use GenServerring.Supervisorring.Link
  require Crdtex
  require Crdtex.Counter

  def init([]), do: {:ok, Crdtex.Counter.new}
  def handle_state_change(_), do: :ok
end

defmodule MultiRingTest do
  use ExUnit.Case, async: false

  test "starting an application with 2 supervisorrings" do

    # init external childs to []
    File.write!("childs_1", :erlang.term_to_binary([]))
    File.write!("childs_2", :erlang.term_to_binary([]))

    # defining rings (or should they be started/supervised by MyApp?)
    {:ok, _} = GenServerring.start_link({:test_ring1, TesterRing})
    {:ok, _} = GenServerring.start_link({:test_ring2, TesterRing})

    # let DHTGenServer manage them
    :ok = DHTGenServer.add_rings([:test_ring1, :test_ring2])

    # we can start MyApp and test
    # :ok = Application.start(MyApp) pas possible : 'Elixir.MyApp.app' manque
    {:ok, _} = Supervisor.start_link(MyApp.Sup, nil)
  end
end
