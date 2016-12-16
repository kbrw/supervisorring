defmodule AddClientTest do
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
  @tag ring_nodes: [:n5, :n6]
  test "adding a child to a running cluster", context do
    ring_name = hd(context.ring_names)
    nodes = Enum.map(context.ring_nodes, fn(n) -> CtUtil.node_name(n) end)
    node_to_add = hd(nodes)

    ring = ConsistentHash.ring_for_nodes(nodes)
    topology =
      RingUtil.get_topology([MySmallApp.SupRing.C1, MySmallApp.SupRing.C2],
        ring, MySmallApp.SupRing)
    topologywithchild =
      RingUtil.get_topology(
        [MySmallApp.SupRing.C1, MySmallApp.SupRing.C2, MySmallApp.SupRing.C3],
        ring,
        MySmallApp.SupRing
      )

    File.write!("childs", :erlang.term_to_binary([]))
    GenServerring.add_node(ring_name, node_to_add)
    :ct.sleep(2_000) # afer two gossips, all nodes should have the complete ring
    DHTGenServer.add_rings(context.ring_names) # ring fully up
    Supervisor.start_link(MySmallApp.Sup, nil)

    assert(topology[node] || [] == RingUtil.local_children(MySmallApp.SupRing))

    c3 = MyApp.SupRing.client_spec(MySmallApp.SupRing.C3)
    case node do
      ^node_to_add -> :supervisorring.start_child(MySmallApp.SupRing, c3)
      _ -> :nothingtodo
    end

    assert(
      topologywithchild[node] ||
      [] == RingUtil.local_children(MySmallApp.SupRing)
    )

    :ct.sleep(2_000)
  end
end
