defmodule MySup do
  use Supervisorring
  
  def migrate({_id, _type, _modules}, old_server, new_server) do
    GenServer.cast(new_server, GenServer.call(old_server, :get))
  end
  
  def init(_arg) do
    strategy = {:one_for_one, 2, 3}
    specs = [
      child_handler(__MODULE__),
      worker(EchoServer, [MySup.C1], id: MySup.C1),
      worker(EchoServer, [MySup.C2], id: MySup.C2)
    ]
    {:ok, {strategy, specs}}
  end
  
  def get_all do
    File.read!("childs") |> :erlang.binary_to_term()
  end
  
  def add(childspec) do
    content = File.read!("childs") |>
      :erlang.binary_to_term() |>
      List.insert_at(0, childspec) |>
      :erlang.term_to_binary()
    File.write!("childs", content)
  end
  
  def del(childid) do
    content = File.read!("childs") |>
      :erlang.binary_to_term() |>
      List.keydelete(childid, 0) |>
      :erlang.term_to_binary()
    File.write!("childs", content)
  end

  def start_link, do: Supervisorring.start_link(MySup, nil, name: __MODULE__)
end

defmodule EchoServer do
  use GenServer

  def start_link(name), do: GenServer.start_link({:local, name}, nil)

  def init(s0), do: {:ok, s0}
  
  def handle_call(:get, _, s), do: {:reply, s, s}
  
  def handle_cast(new_state, _), do: {:noreply, new_state}
end

defmodule MultiNodeTest do
  use ExUnit.Case

  @nodes ["dev1","dev2","dev3","dev4"] |> Enum.map(&(:"#{&1}@127.0.0.1"))

  defp sync(sync_atom, master_node) do
    case node() do
      ^master_node ->
	@nodes |> Enum.filter(&(&1 != master_node)) |> Enum.each(&(send {:testserver, &1}, sync_atom))
      _ ->
	receive do
          ^sync_atom -> :ok
        after 30000 ->
	    exit(:impossiblesync)
        end
    end
    IO.puts "sync : #{sync_atom}"
  end

  test "a supervisoring of one gen_server should" do
    Process.flag(:trap_exit, true)
    Process.register(self(), :testserver)

    # init external childs to []
    File.write!("childs", :erlang.term_to_binary([]))

    # master node send sync message to others
    master_node = @nodes |> List.first()
    
    merger = fn _, v1, v2 -> v1 ++ v2 end

    # calculate targeted topology [nodename: [id1,id2,..], nodename2: [idx,...]]
    ring = ConsistentHash.new(@nodes)
    topology = [MySup.C1, MySup.C2] |> Enum.reduce([], fn server, acc ->
      Keyword.merge(acc, [{ConsistentHash.get_node(ring, {MySup, server}), [server]}], merger)
    end)
    
    # calculate targeted topology with new child c3 : [nodename: [id1,id2,..], nodename2: [idx,...]]
    ring = ConsistentHash.new(@nodes)
    topology_withchild = [MySup.C1, MySup.C2, MySup.C3] |> Enum.reduce([], fn server, acc ->
      Keyword.merge(acc, [{ConsistentHash.get_node(ring, {MySup, server}), [server]}], merger)
    end)

    # calculate targeted topology if one node die [nodename: [id1,id2,..], nodename2: [idx,...]]
    c1node = ConsistentHash.get_node(ring, {MySup, MySup.C1})
    c1nodedownring = ConsistentHash.new(@nodes |> Enum.filter(&(&1 != c1node)))
    topology_nodedown = [MySup.C1, MySup.C2, MySup.C3] |> Enum.reduce([], fn server, acc ->
      Keyword.merge(acc, [{ConsistentHash.get_node(c1nodedownring, {MySup, server}), [server]}], merger)
    end)

    # start test supervisor
    {:ok, _} = MySup.start_link

    # sync all nodes before tests
    receive do after 1000 -> :ok end
    sync(:start_sync, master_node)
    receive do after 1000 -> :ok end

    # assert topology on each node is OK 
    local_children = :supervisor.which_children(MySup) |> Enum.map(fn {id, _, _, _} -> id end)
    assert(topology[node()] || ([] == local_children))

    # add dynamic child
    sync(:add_childs, master_node)
    c3 = {MySup.C3,
	  {:gen_server, :start_link, [{:local, MySup.C3}, EchoServer, nil, []]},
	  :permanent, 2, :worker, [GenericServer]}
    :supervisorring.start_child(MySup, c3)
    
    # assert topology on each node match, even with the new child
    local_children = :supervisor.which_children(MySup) |> Enum.map(fn {id, _, _, _} -> id end)
    assert(topology_withchild[node()] || ([] == local_children))

    # terminate one node:
    if node() == c1node do
      :init.stop
      exit(:normal)
    end

    # wait ring up to date
    sync(:wait_ring_update, master_node)
    receive do after 4000 -> :ok end

    # assert new topology
    local_children = :supervisor.which_children(MySup) |> Enum.map(fn {id, _, _, _} -> id end)
    assert(topology_nodedown[node()] || ([] == local_children))

    # end
    sync(:end_sync, master_node)
  end
end
