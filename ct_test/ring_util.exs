defmodule RingUtil do
  def get_topology(set, ring, sup) do
    merge_args =
      fn(rng, srv) ->
        [{ConsistentHash.node_for_key(rng, {sup, srv}), [srv]}]
      end

    reduce_fun =
      fn(server, acc) ->
        acc
        |> Dict.merge(merge_args.(ring, server), fn _, v1, v2 -> v1 ++ v2 end)
      end

    Enum.reduce(set, [], reduce_fun)
  end

  def local_children(sup),
    do: :supervisor.which_children(sup) |> Enum.map fn {id, _, _, _} -> id end
end
