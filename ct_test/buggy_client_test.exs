defmodule BuggyClientTest do
  use ExUnit.Case, async: true

  setup context do
    CtUtil.gen_setup(context)

    on_exit fn() ->
      Application.stop(:supervisorring)
      Application.stop(:crdtex)
    end

    :ok
  end

  @tag ring_names: [:test_ring1, :test_ring2]
  @tag ring_nodes: [:n1, :n2, :n3, :n4]
  # basically the same test than the one done by multi_ring.exs but on several
  # nodes :)
  test "handling of a buggy client", context do
    # initialize
    File.write!("childs_1", :erlang.term_to_binary([]))
    File.write!("childs_2", :erlang.term_to_binary([]))

    # start « App »
    Supervisor.start_link(MyApp.Sup, nil)

    # add all nodes to the rings
    for ring <- context.ring_names,
        node_name <- context.ring_nodes,
        do: add_node(ring, node_name)

    :ct.sleep(5_500)

    client = MyApp.SupRing1.C1
    sup_ref = MyApp.SupRing1
    client_node = :supervisorring.find(sup_ref, client)
    filter_fun = fn({id, _, _, _} = child) -> id == client end

    # picture before first crash
    [{client, client_pid,_, _}] =
      Enum.filter(Supervisorring.which_children(sup_ref), filter_fun)
    local_sup_ref_pid = n2pid({client_node, sup_ref})
    global_sup_ref_pid =
      n2pid({client_node, Supervisorring.global_sup_ref(sup_ref)})

    # one crash, client_pid changed
    fail_client(client, sup_ref, 1)
    [{client, client_pid2,_, _}] =
      Enum.filter(Supervisorring.which_children(sup_ref), filter_fun)
    assert client_pid2 != client_pid
    assert local_sup_ref_pid == n2pid({client_node, sup_ref})

    # one more crash, local_sup should still be here
    fail_client(client, sup_ref, 1)
    assert local_sup_ref_pid == n2pid({client_node, sup_ref})

    # one more crash, local_sup should have restarted too but not global_sup
    fail_client(client, sup_ref, 1)
    assert local_sup_ref_pid != n2pid({client_node, sup_ref})
    assert global_sup_ref_pid ==
      n2pid({client_node, Supervisorring.global_sup_ref(sup_ref)})

    # eight more crashes, global_sup should still be here
    fail_client(client, sup_ref, 8)
    assert global_sup_ref_pid ==
      n2pid({client_node, Supervisorring.global_sup_ref(sup_ref)})

    # finally global_sup is restarted also
    fail_client(client, sup_ref, 1)
    assert global_sup_ref_pid !=
      n2pid({client_node, Supervisorring.global_sup_ref(sup_ref)})

    :ct.sleep(2_000)
  end

  defp add_node(r, n) do
    :ct.sleep(50) # give time to DHTGenServer to recompute rings
    GenServerring.add_node(r, CtUtil.node_name(n))
  end

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

  defp n2pid({node_, name}), do: :rpc.call(node_, Process, :whereis, [name])
  defp n2pid(name), do: Process.whereis(name)
end
