defmodule N1Test do
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
  @tag supervisors: [MyApp.SupRing1, MyApp.SupRing2]
  test "all clients usable on all nodes", context do

    # initialize
    File.write!("childs_1", :erlang.term_to_binary([]))
    File.write!("childs_2", :erlang.term_to_binary([]))

    # start « App »
    DHTGenServer.add_rings(context.ring_names) # empty rings
    Supervisor.start_link(MyApp.Sup, nil)

    # give time to gossips to add  nodes to the rings
    :ct.sleep(5_000)

    # set all the clients state
    Enum.each(context.supervisors, fn(s) -> set_all_clients(s) end)


    # check that all clients have been set
    for sup <- context.supervisors,
        client <- all_clients(sup),
        do: assert client == get_client(sup, client)

    :ct.sleep(2_000)
  end

  defp all_clients(sup) do
    clients = ["C1", "C2", "C3", "C4", "C5", "C6"]
    for client <- clients, do: :"#{sup}.#{client}"
  end

  defp add_node(r, n) do
    :ct.sleep(50) # give time to DHTGenServer to recompute rings
    GenServerring.add_node(r, CtUtil.node_name(n))
  end

  defp set_client(s, c), do: set_client(s, c, c)
  defp set_client(s, c, v),
    do: GenServer.cast({c, :supervisorring.find(s, c)}, v)

  defp get_client(s, c),
    do: GenServer.call({c, :supervisorring.find(s, c)}, :get)

  defp set_all_clients(sup),
    do: Enum.each(all_clients(sup), fn(c) -> set_client(sup, c) end)
end
