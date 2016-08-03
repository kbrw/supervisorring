Code.require_file "test_helper.exs", __DIR__

defmodule MySup do
  use Supervisorring

  def migrate({_id, _type, _modules}, old_server, new_server),
    do: :gen_server.cast(new_server, :gen_server.call(old_server, :get))

  def client_spec(name, shutdown \\ 2) do
    {name,
      {:gen_server, :start_link, [{:local, name}, GenericServer, nil, []]},
      :permanent, shutdown, :worker, [GenericServer]}
  end

  def init(_arg) do
    {:ok, {{:one_for_one, 10, 3}, [
      {:dyn_child_handler, __MODULE__},
      client_spec(MySup.C1, 50),
      client_spec(MySup.C2, 50)
    ]}}
  end

  @behaviour :dyn_child_handler

  def match(_), do: true

  def get_all, do: File.read!("childs") |> :erlang.binary_to_term

  def add(childspec) do
    File.write!(
      "childs",
      File.read!("childs")
      |> :erlang.binary_to_term
      |> List.insert_at(0, childspec)
      |> :erlang.term_to_binary)
  end

  def del(childid) do
    File.write!(
      "childs",
      File.read!("childs")
      |> :erlang.binary_to_term
      |> List.keydelete(childid, 0)
      |> :erlang.term_to_binary)
  end

  def start_link,
    do: :supervisorring.start_link({:local, __MODULE__}, MySup, nil)
end

defmodule GenericServer do
  use GenServer

  def start_link(_), do: {:ok, nil}

  def handle_call(:get, _, s), do: {:reply, s, s}

  def handle_cast(new_state, _), do: {:noreply, new_state}
end

defmodule MultiNodeTest do
  use ExUnit.Case
  import Enum
  @nodes ["dev1", "dev2", "dev3", "dev4"] |> map(&(:"#{&1}@127.0.0.1"))

  defp sync(sync_atom, master_node) do
    case node do
      ^master_node ->
        @nodes
        |> filter(&(&1!=master_node))
        |> each &(send {:testserver, &1}, sync_atom)
      _ ->
        receive do
          ^sync_atom -> :ok
          after 30000 -> exit(:impossiblesync)
        end
    end
    IO.puts "sync: #{sync_atom}"
  end

  # calculate targeted topology [nodename: [id1, id2, ..], nodename2:
  # [idx, ...]]
  defp get_topology(set, ring) do
    merge_args =
      fn(rng, srv) ->
        [{ConsistentHash.node_for_key(rng, {MySup, srv}), [srv]}]
      end

    reduce_fun =
      fn(server, acc) ->
        acc
        |> Dict.merge(merge_args.(ring, server), fn _, v1, v2 -> v1 ++ v2 end)
      end

    reduce(set, [], reduce_fun)
  end

  defp local_children,
    do: :supervisor.which_children(MySup) |> Enum.map fn {id, _, _, _} -> id end

  defp add_nodes(master_node, master_node) do
    add_node_to_ring =
      fn(n) ->
        :ok = GenServerring.add_node(:test_ring, n)
        receive do after 1200 -> :ok end
      end
    each(@nodes |> filter(&(&1 != master_node)), add_node_to_ring)
  end
  defp add_nodes(_, _) do
    wait = fn(_) -> receive do after 1200 -> :ok end end
    each(@nodes |> filter(&(&1 != node())), wait)
  end

  test "a supervisoring of one gen_server should" do
    Process.register(self, :testserver)

    # init external childs to []
    File.write!("childs", :erlang.term_to_binary([]))

    ring = ConsistentHash.ring_for_nodes(@nodes)
    topology = get_topology([MySup.C1, MySup.C2], ring)

    # topology with an extra child
    topology_withchild = get_topology([MySup.C1, MySup.C2, MySup.C3], ring)

    # topology after a node crash
    c1node = ConsistentHash.node_for_key(ring, {MySup, MySup.C1})
    c1nodedownring =
      ConsistentHash.ring_for_nodes(@nodes |> filter(&(&1 != c1node)))
    topology_nodedown =
      get_topology([MySup.C1, MySup.C2, MySup.C3], c1nodedownring)

    # master node send sync message to others
    master_node = # don't pick the one we are going to crash...
      @nodes
      |> filter(&(&1 != c1node))
      |> List.first

    #sync all nodes before tests
    receive do after 1000 -> :ok end
    sync(:start_sync, master_node)
    receive do after 1000 -> :ok end

    #start test supervisor
    {:ok, my_sup_pid} = MySup.start_link

    # add nodes to the ring should make the test less boring
    sync(:adding_nodes, master_node)
    add_nodes(node, master_node)
    sync(:nodes_added, master_node)

    receive do after 3000 -> :ok end # let gossips happen

    #assert topology on each node is OK
    assert(topology[node] || [] == local_children())

    #add dynamic child
    sync(:add_childs, master_node)
    c3 = MySup.client_spec(MySup.C3, 50)
    case node do
      ^master_node -> :supervisorring.start_child(MySup, c3)
      _ -> :nothingtodo
    end
    sync(:child_added, master_node, true)


    #assert topology on each node match, even with the new child
    assert(topology_withchild[node] || [] == local_children())

    receive do after 3_000 -> :ok end


    sync(:crash_node, master_node, true)
    # terminate one node :
    if node == c1node do
			#(:init.stop; exit(:normal))
      # not using the proper way of stopping a node as I want to test a node
      # crash and not a node being stopped
      [sname | _] = Regex.split(~r/@/, Atom.to_string(c1node))
      {:ok, cwd} = File.cwd
      System.cmd(cwd <> "/kill-erlang-node.sh", [sname])
		end
    sync(:node_crashed, master_node, true)

    #assert new topology
    assert(topology_nodedown[node] || [] == local_children())

    assert(Process.alive?(my_sup_pid))
    sync(:end_sync, master_node)
  end
end
