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
  @tag ring_nodes: [:n5, :n6, :n7, :n8]
  test "adding a child to a running cluster", context do
    ring_name = hd(context.ring_names)
    node_to_add = CtUtil.node_name(hd(context.ring_nodes))

    ring = ConsistentHash.ring_for_nodes(context.ring_nodes)
    topology =
      RingUtil.get_topology(
        [MySmallApp.Sup.C1, MySmallApp.Sup.C2],
        ring,
        MySmallApp.Sup
      )
    topologywithchild =
      RingUtil.get_topology(
        [MySmallApp.Sup.C1, MySmallApp.Sup.C2, MySmallApp.Sup.C3],
        ring,
        MySmallApp.Sup
      )

    File.write!("childs", :erlang.term_to_binary([]))
    Supervisor.start_link(MySmallApp.Sup, nil)
    GenServerring.add_node(ring_name, node_to_add)
    :ct.sleep(5_000) # afer five gossip, all nodes should have the complete ring

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
