Code.require_file "test_helper.exs", __DIR__

defmodule ChashTest do
  use ExUnit.Case
  import Enum
  import ConsistentHash

  @nb_key 1000
  @test_set 1..@nb_key |> Enum.map fn _ -> :crypto.rand_bytes(100) end
  @nodes [:n1,:n2,:n3,:n4,:n5,:n6,:n7]

  test "each node should be assign to roughly the same nb of keys" do
    ring = ring_for_nodes(@nodes)
    res_set = @test_set |> map(fn k -> node_for_key(ring,k) end)
    counts = @nodes |> Enum.map fn n -> (res_set |> Enum.count &(&1==n)) end
    mean = @nb_key/length(@nodes)
    assert(counts|>Enum.all?(&(abs(&1-mean) < mean*0.3)))
  end

  test "if we remove a node, only ~nb_keys/nb_node keys have to move" do
     ring = ring_for_nodes(@nodes)
     ring2 = ring_for_nodes(@nodes ++ [:n8])
     res1_set = @test_set |> map(fn k -> {k,node_for_key(ring,k)} end) 
     IO.inspect res1_set
     res2_set = @test_set |> map(fn k -> {k,node_for_key(ring2,k)} end) 
     diff = Set.difference(Enum.into(res1_set, HashSet.new), Enum.into(res2_set, HashSet.new)) |> Set.size
     mean_per_node = Enum.count(@test_set)/length(@nodes)
     assert(diff < mean_per_node*1.1)
  end
end
