defmodule ChashTest do
  use ExUnit.Case

  @nb_key 1000
  @test_set 1..@nb_key |> Enum.map(fn _ -> :crypto.strong_rand_bytes(100) end)
  @nodes [:n1, :n2, :n3, :n4, :n5, :n6, :n7]

  test "each node should be assign to roughly the same nb of keys" do
    ring = ConsistentHash.new(@nodes)
    res_set = @test_set |> Enum.map(fn k -> ConsistentHash.get_node(ring, k) end)
    counts = @nodes |> Enum.map(fn n -> (Enum.count(res_set, &(&1 == n))) end)
    mean = @nb_key / length(@nodes)
    assert(counts |> Enum.all?(&(abs(&1-mean) < mean*0.3)))
  end

  test "if we remove a node, only ~nb_keys/nb_node keys have to move" do
     ring = ConsistentHash.new(@nodes)
     ring2 = ConsistentHash.new(@nodes ++ [:n8])
     res1_set = @test_set |> Enum.map(fn k -> {k, ConsistentHash.get_node(ring, k)} end) 
     IO.inspect res1_set
     
     res2_set = @test_set |> Enum.map(fn k -> {k, ConsistentHash.get_node(ring2, k)} end) 
     diff = MapSet.difference(
       Enum.into(res1_set, MapSet.new()),
       Enum.into(res2_set, MapSet.new())) |>
       MapSet.size()
     mean_per_node = Enum.count(@test_set)/ length(@nodes)
     assert(diff < mean_per_node*1.1)
  end
end
