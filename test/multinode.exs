Code.require_file "test_helper.exs", __DIR__

defmodule MySup do
  @behaviour :supervisorring
  def migrate({_id,_type,_modules},old_server,new_server), do:
    :gen_server.cast(new_server,:gen_server.call(old_server,:get))
  def init(_arg) do
    {:ok,{{:one_for_one,2,3},[
      {:dyn_child_handler,__MODULE__},
      {MySup.C1,{:gen_server,:start_link,[{:local,MySup.C1},GenericServer,nil,[]]},:permanent,2,:worker,[GenericServer]},
      {MySup.C2,{:gen_server,:start_link,[{:local,MySup.C2},GenericServer,nil,[]]},:permanent,2,:worker,[GenericServer]}
    ]}}
  end
  @behaviour :dyn_child_handler
  def match(_), do: true
  def get_all, do:
    File.read!("childs")|>:erlang.binary_to_term
  def add(childspec), do:
    File.write!("childs",File.read!("childs") |> :erlang.binary_to_term |> List.insert_at(0,childspec) |> :erlang.term_to_binary)
  def del(childid), do:
    File.write!("childs",File.read!("childs") |> :erlang.binary_to_term |> List.keydelete(childid,0) |> :erlang.term_to_binary)

  def start_link, do: :supervisorring.start_link({:local,__MODULE__},MySup,nil)
end
defmodule GenericServer do
  use GenServer.Behaviour
  def handle_call(:get,_,s), do: {:reply,s,s}
  def handle_cast(new_state,_), do: {:noreply,new_state}
end

defmodule MultiNodeTest do
  use ExUnit.Case
  import Enum
  @nodes ["dev1","dev2","dev3","dev4"] |> map(&(:"#{&1}@127.0.0.1"))
  defp sync(sync_atom,master_node) do
    case node do
      ^master_node-> @nodes|>filter(&(&1!=master_node))|>each &(send {:testserver,&1}, sync_atom)
      _ -> receive do
             ^sync_atom -> :ok
             after 30000 -> exit(:impossiblesync)
           end
    end
    IO.puts "sync : #{sync_atom}"
  end

  test "a supervisoring of one gen_server should" do
    Process.flag(:trap_exit,true)
    Process.register(self,:testserver)

    # init external childs to []
    File.write!("childs",[]|>:erlang.term_to_binary)

    #master node send sync message to others
    master_node = @nodes |> List.first

    #calculate targeted topology [nodename: [id1,id2,..], nodename2: [idx,...]]
    ring = ConsistentHash.new(@nodes)
    topology = [MySup.C1,MySup.C2]|>reduce([],fn server,acc ->
      acc |> Dict.merge([{ConsistentHash.node_for_key(ring,{MySup,server}),[server]}],fn _,v1,v2->v1++v2 end)
    end)
    #calculate targeted topology with new child c3 : [nodename: [id1,id2,..], nodename2: [idx,...]]
    ring = ConsistentHash.new(@nodes)
    topology_withchild = [MySup.C1,MySup.C2,MySup.C3]|>reduce([],fn server,acc ->
      acc |> Dict.merge([{ConsistentHash.node_for_key(ring,{MySup,server}),[server]}],fn _,v1,v2->v1++v2 end)
    end)
    #calculate targeted topology if one node die [nodename: [id1,id2,..], nodename2: [idx,...]]
    c1node = ConsistentHash.node_for_key(ring,{MySup,MySup.C1})
    c1nodedownring = ConsistentHash.new(@nodes|>filter(&(&1!=c1node)))
    topology_nodedown = [MySup.C1,MySup.C2,MySup.C3]|>reduce([],fn server,acc ->
      acc |> Dict.merge([{ConsistentHash.node_for_key(c1nodedownring,{MySup,server}),[server]}],fn _,v1,v2->v1++v2 end)
    end)

    #start test supervisor
    {:ok,_} = MySup.start_link

    #sync all nodes before tests
    receive do after 1000->:ok end
    sync(:start_sync,master_node)
    receive do after 1000->:ok end

    #assert topology on each node is OK 
    local_children = :supervisor.which_children(MySup) |> Enum.map fn {id,_,_,_}->id end
    assert(topology[node]||[]==local_children)

    #add dynamic child
    sync(:add_childs,master_node)
    c3 = {MySup.C3,{:gen_server,:start_link,[{:local,MySup.C3},GenericServer,nil,[]]},:permanent,2,:worker,[GenericServer]}
    :supervisorring.start_child(MySup,c3)
    #assert topology on each node match, even with the new child
    local_children = :supervisor.which_children(MySup) |> Enum.map fn {id,_,_,_}->id end
    assert(topology_withchild[node]||[]==local_children)

    #terminate one node :
    if node == c1node, do: (:init.stop;exit(:normal))

    #wait ring up to date
    sync(:wait_ring_update,master_node)
    receive do after 4000->:ok end

    #assert new topology
    local_children = :supervisor.which_children(MySup) |> Enum.map fn {id,_,_,_}->id end
    assert(topology_nodedown[node]||[]==local_children)

    #end
    sync(:end_sync,master_node)
  end
end
