defmodule ConsistentHash do
  @moduledoc """
  Consistent hashing key/node mapping
  """
  @typedoc "Structure holding a ring"
  @type t :: node | {node, node, node}

  @vnode_per_node 300
  
  @doc """
  Generates a new ring with given nodes

  Place nodes at `@vnode_per_node` dots in the key hash space
  {hash(node ++ vnode_idx), node}, then create a bst adapted to
  consistent hashing traversal, for a given hash, find the next vnode
  dot in the ring
  """
  @spec new(Enumerable.t) :: t
  def new(nodes) do
    vnodes = nodes |>
      Enum.flat_map(fn n -> 1..@vnode_per_node |> Enum.map(&{key_as_int("#{n}#{&1}"), n}) end) |>
      Enum.sort(fn {h1, _}, {h2, _} -> h2 > h1 end)
    
    bsplit(vnodes, {0, trunc(:math.pow(2, 160) - 1)}, List.first(vnodes))
  end

  @doc """
  Map a given key to a node of the ring in a consistent way (ring modifications move a minimum of keys)
  """
  @spec node_for_key(t, term) :: node
  def node_for_key(ring, key), do: bfind(key_as_int(key),ring)

  # "place each term into int hash space : term -> 160bits bin -> integer"
  defp key_as_int(key),do: :crypto.hash(:sha, :erlang.term_to_binary(key)) |> hash_as_int
  defp hash_as_int(<<key::size(160)-integer>>),do: key

  # dedicated binary search tree, middle split each interval (easy tree
  # balancing) except when only one vnode is there (split at vnode hash)
  defp bsplit([],{_,_},{_,next}), do: next # if no vnode dot in interval, take next node in the ring 
  defp bsplit([{h,n}],{_,_},{_,next}), do: {h,n,next} # interval contains a vnode split
  defp bsplit(list,{lbound,rbound},next) do # interval contains multiple vnode, recursivly middle split allows easy tree balancing
    center = lbound + (rbound - lbound)/2
    {left,right} = list |> Enum.split_while(fn {h,_n}->h<center end)
    {center,bsplit(left,{lbound,center},(right|>List.first)||next),bsplit(right,{center,rbound},next)}
  end
  # bsplit is designed to allow standard btree traversing to associate node to hash
  defp bfind(_,node) when is_atom(node), do: node
  defp bfind(k,{center,_,right}) when k > center, do: bfind(k,right)
  defp bfind(k,{center,left,_}) when k <= center, do: bfind(k,left)
end
