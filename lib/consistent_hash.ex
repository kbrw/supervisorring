defmodule ConsistentHash do
  @docmodule "consistent hashing key/node mapping"
  import Enum
  use Bitwise, only_operators: true

  @doc """
  Map a given key to a node of the ring in a consistent way (ring modifications
  move a minimum of keys)
  """
  def node_for_key(ring, key), do: bfind(key_as_int(key), ring)

  @vnode_per_node 300
  @doc "generate the node_for_key ring parameter according to a given node list"
  def ring_for_nodes(nodes) do
    # Place nodes at @vnode_per_node dots in the key hash space
    # {hash(node ++ vnode_idx), node},
    # then create a bst adapted to consistent hashing traversal, for a given
    # hash, find the next vnode dot in the ring
    map_fun =
        fn n -> 1..@vnode_per_node |> map(&{key_as_int("#{n}#{&1}"), n}) end
    vnodes =
      nodes
      |> flat_map(map_fun)
      |> sort(fn {h1, _}, {h2, _} -> h2 > h1 end)
    vnodes |> bsplit({0, (2 <<< 160) - 1}, vnodes |> List.first)
  end

  # "place each term into int hash space : term -> 160bits bin -> integer"
  defp key_as_int(key) do
    hash = :crypto.hash(:sha, :erlang.term_to_binary(key))
    <<key:: size(160) - integer>> = hash
    key
  end

  # dedicated binary search tree, middle split each interval (easy tree
  # balancing) except when only one vnode is there (split at vnode hash)

  # if no vnode dot in interval, take next node in the ring
  defp bsplit([], {_, _}, {_, next}), do: next
  # interval contains a vnode, split
  defp bsplit([{h, n}], {_, _}, {_, next}), do: {h, n, next}
  # interval contains multiple vnode, recursivly middle split allows easy tree
  # balancing
  defp bsplit(list, {lbound, rbound}, next) do
    center = lbound + (rbound - lbound) / 2
    {left, right} = list |> split_while(fn {h, _n} -> h < center end)
    {center,
     bsplit(left, {lbound, center}, (right |> List.first) || next),
     bsplit(right, {center, rbound}, next)}
  end

  # bsplit is designed to allow standard btree traversing to associate node to
  # hash
  defp bfind(_, node_name) when is_atom(node_name), do: node_name
  defp bfind(k, {center, _, right}) when k > center, do: bfind(k, right)
  defp bfind(k, {center, left, _}) when k <= center, do: bfind(k, left)
end
