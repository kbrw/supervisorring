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
  def start_link(_), do: GenServer.start_link(__MODULE__, 0)
  def init(s), do: {:ok, s}
  def handle_call(:get, _, s), do: {:reply, s, s}
  # next cast is forcing the client to fail
  def handle_cast(:berzek, s) do
    _ = 1 + s
    {:noreply, s}
  end
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

  defp fail_client(client, supervisor, n) do
    run_node = :supervisorring.find(supervisor, client)
    fail_client({client, run_node}, n)
  end

  defp fail_client(_, 0), do: :ok
  defp fail_client(client, n) do
    GenServer.cast(client, :berzek)
    receive do after 5 -> :ok end # let's give enough time for a restart
    fail_client(client, n - 1)
  end

  defp n2pid(name), do: Process.whereis(name)

  test "starting an application with 2 supervisorrings" do

    # init external childs to []
    File.write!("childs_1", :erlang.term_to_binary([]))
    File.write!("childs_2", :erlang.term_to_binary([]))

    # defining rings
    {:ok, _} = GenServerring.start_link({:test_ring1, TesterRing})
    {:ok, _} = GenServerring.start_link({:test_ring2, TesterRing})

    # let DHTGenServer manage them
    :ok = DHTGenServer.add_rings([:test_ring1, :test_ring2])

    # we can start MyApp and test
    # :ok = Application.start(MyApp) pas possible : 'Elixir.MyApp.app' manque
    {:ok, _} = Supervisor.start_link(MyApp.Sup, nil)

    sup_ref = MyApp.SupRing1
    sup_ref2 = MyApp.SupRing2
    client = MyApp.SupRing1.C1
    super_sup = Supervisorring.App.Sup.SuperSup
    filter_fun = fn({id, _, _, _} = child) -> id == client end

    # take a picture before crashing the client
    [{client, client_pid,_, _}] =
      Enum.filter(Supervisor.which_children(sup_ref), filter_fun)
    local_sup_ref_pid = n2pid(sup_ref)
    local_sup_ref2_pid = n2pid(sup_ref2)
    global_sup_ref_pid = n2pid(Supervisorring.global_sup_ref(sup_ref))
    super_sup_pid = n2pid(super_sup)

    # one crash, only client should have changed
    fail_client(client, sup_ref, 1)
    [{client, client_pid2,_, _}] =
      Enum.filter(Supervisor.which_children(sup_ref), filter_fun)
    assert client_pid2 != client_pid
    assert local_sup_ref_pid == n2pid(sup_ref)
    assert global_sup_ref_pid == n2pid(Supervisorring.global_sup_ref(sup_ref))
    assert super_sup_pid == n2pid(super_sup)

    # one crash, local_sup should still be there
    fail_client(client, sup_ref, 1)
    assert local_sup_ref_pid == n2pid(sup_ref)

    # one more crash, local_sup should have restarted too
    fail_client(client, sup_ref, 1)
    assert local_sup_ref_pid != n2pid(sup_ref)
    assert global_sup_ref_pid == n2pid(Supervisorring.global_sup_ref(sup_ref))
    assert super_sup_pid == n2pid(super_sup)

    # five more crashes, global_sup should still be there
    fail_client(client, sup_ref, 5)
    assert global_sup_ref_pid == n2pid(Supervisorring.global_sup_ref(sup_ref))
    assert super_sup_pid == n2pid(super_sup)

    # final straw on the camel back global_sup_ref and super_sup affected but
    # ring2 should be unaffected 
    # why do we need to reach 12 restart of buggy client before getting a
    # restart of global_sup? I was expecting 9, not 12
    fail_client(client, sup_ref, 4)
    assert global_sup_ref_pid != n2pid(Supervisorring.global_sup_ref(sup_ref))
    assert super_sup_pid == n2pid(super_sup)
    assert local_sup_ref2_pid == n2pid(sup_ref2)

  end
end
