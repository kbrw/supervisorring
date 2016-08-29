defmodule CrashNodeTest do
  use ExUnit.Case, async: true

  setup context do
    CtUtil.gen_setup(context)
    
    on_exit fn() ->
      Application.stop(:supervisorring)
      Application.stop(:crdtex)
    end

    :ok
  end
  
  @tag ring_names: [:test_ring]
  @tag ring_nodes: [:n7, :n8, :n9]
  test "crashing a node", context do
    ring_name = hd(context.ring_names)
    nodes = Enum.map(context.ring_nodes, fn(n) -> CtUtil.node_name(n) end)
    node_to_add = hd(nodes)

    ring = ConsistentHash.ring_for_nodes(nodes)
    topology =
      RingUtil.get_topology([MySmallApp.SupRing.C1, MySmallApp.SupRing.C2],
        ring, MySmallApp.SupRing)

    c1node =
      ConsistentHash.node_for_key(ring,
        {MySmallApp.SupRing, MySmallApp.SupRing.C1})
    nodes_after_crash = Enum.filter(nodes, &(&1 != c1node))
    c1nodedownring = ConsistentHash.ring_for_nodes(nodes_after_crash)
    topology_nodedown =
      RingUtil.get_topology([MySmallApp.SupRing.C1, MySmallApp.SupRing.C2],
        c1nodedownring, MySmallApp.SupRing)


    File.write!("childs", :erlang.term_to_binary([]))
    DHTGenServer.add_rings(context.ring_names) # empty ring
    Supervisor.start_link(MySmallApp.Sup, nil)
    GenServerring.add_node(ring_name, node_to_add)
    :ct.sleep(5_000) # afer five gossip, all nodes should have the complete ring

    assert(topology[node] || [] == RingUtil.local_children(MySmallApp.SupRing))

    first_node = hd(nodes_after_crash)
    case node do
      ^first_node ->
        [sname | _] = Regex.split(~r/@/, Atom.to_string(c1node))
        test_dir = :erlang.list_to_binary(:ct_elixir_wrapper.test_dir())
        {"", 0} = System.cmd(test_dir <> "/../kill-erlang-node.sh", [sname])
      _ -> :nothingtodo
    end

    :ct.sleep(3)
    assert Enum.member?(Node.list, c1node) == false
    assert(
      topology_nodedown[node] ||
      [] == RingUtil.local_children(MySmallApp.SupRing)
    )

    :ct.sleep(2_000)
  end
end
