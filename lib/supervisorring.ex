defmodule Supervisorring do
  use GenEvent.Behaviour
  defrecord State, ring: nil, servers: HashMap.new
  import Enum
  @doc "Small process distribution server"
  def start_link, do: :gen_server.start_link({:local,__MODULE__},__MODULE__,[],[])
  def init(_), do: {:ok,HashSet.new}

  def handle_event({:new_ring,oldring,newring},state) do
    case {oldring.up_set|>to_list,newring.up_set|>to_list} do
        {unchange,unchange}-> {:ok,state}
        {_,newnodes} -> {:ok,state.ring(ConstHash.ring_for_nodes(newnodes))}
    end
  end

  def handle_call({:new_proc,key,_args},_from,procset) do
    node = node_for_key(key,:gen_server.call(NanoRing,:get_up) |> Enum.to_list)
    {:reply,node,procset}
  end

  defmodule ConstHash do
    @docmodule "consistent hashing key/node mapping"

    @doc "Map a given key to a node of the ring in a consistent way (ring modifications move a minimum of keys)"
    def node_for_key(key,ring), do: bfind(key,ring)

    @vnode_per_node 300
    @doc "generate the node_for_key ring parameter according to a given node list"
    def ring_for_nodes(nodes) do
      #Place nodes at @vnode_per_node dots in the hash space {hash(node++vnode_idx),node},
      #then create a bst adapted to consistent hashing traversal, for a given hash, find the next vnode dot in the ring
      vnodes = nodes |> flat_map(fn n -> (1..@vnode_per_node |> map &{key_as_int("#{n}#{&1}"),n}) end) 
      vnodes |> bsplit({0,trunc(:math.pow(2,160)-1)},vnodes|>first)
    end

    # "place each term into int hash space : term -> 160bits bin -> integer"
    defp key_as_int(<<key::[size(160),integer]>>),do: key
    defp key_as_int(key),do: (key |> term_to_binary |> :crypto.sha |> key_as_int)

    # dedicated binary search tree, middle split each interval (easy tree
    # balancing) except when only one vnode is there (split at vnode hash)
    defp bsplit([],{_,_},{_,next}), do: next # if no vnode dot in interval, take next node in the ring 
    defp bsplit([{h,n}],{_,_},{_,next}), do: {h,n,next} # interval contains a vnode split
    defp bsplit(list,{lbound,rbound},next) do # interval contains multiple vnode, recursivly middle split allows easy tree balancing
      center = lbound + (rbound - lbound)/2
      {left,right} = list |> partition(fn {h,_n}->h<center end)
      {center,bsplit(left,{lbound,center},(right|>first)||next),bsplit(right,{center,rbound},next)}
    end
    # bsplit is designed to allow standard btree traversing to associate node to hash
    defp bfind(_,node) when is_atom(node), do: node
    defp bfind(k,{center,_,right}) when k > center, do: bfind(k,right)
    defp bfind(k,{center,left,_}) when k <= center, do: bfind(k,left)
  end
end

defmodule Supervisorring.App do
  use Application.Behaviour
  def start(_type,_args) do
    :supervisor.start_link(Supervisorring.App.Sup,[])
  end
  defmodule Sup do
    use Supervisor.Behaviour
    def init([]) do
      supervise([
        worker(:gen_event,[{:local,NanoRing.Events}], id: NanoRing.Events),
        worker(NanoRing,[])
      ], strategy: :one_for_one)
    end
  end
end
