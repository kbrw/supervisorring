Code.require_file "test_helper.exs", __DIR__

defmodule NanoProcDistTest do
  use ExUnit.Case
  import Enum
  import NanoProcDist

  @nb_key 1000
  @test_set 1..@nb_key |> Enum.map fn _ -> :crypto.rand_bytes(100) end
  @nodes [:n1,:n2,:n3,:n4,:n5,:n6,:n7]

  #test "every key should give a node" do
  #  assert(@test_set |> Enum.map(&NanoProcDist.node_for_key(&1,@nodes)) |> Enum.all?)
  #end

  #test "results should be the same as chash" do
  #  chash_ring = chash_ring(@nodes)
  #  IO.puts inspect chash_ring
  #  res_chash = @test_set |> Enum.map(fn k -> {k,:chash.successors(:chash.key_of(k),chash_ring,1) |> Enum.at(0) |> elem(1)} end) |> HashSet.new
  #  res_set = @test_set |> Enum.map(fn k -> {k,NanoProcDist.node_for_key(k,@nodes)} end) |> HashSet.new
  #  assert res_set == res_chash
  #end

  test "each node should be assign to roughly the same nb of keys" do
    ring = ring_for_nodes(@nodes)
    res_set = @test_set |> map(fn k -> node_for_key(key_as_int(k),ring) end)
    counts = @nodes |> Enum.map fn n -> (res_set |> Enum.count &(&1==n)) end
    IO.puts inspect counts
  end

  test "if we remove a node, only nb_keys/nb_node keys have to move" do
     ring = ring_for_nodes(@nodes)
     nodes = @nodes ++ [:n8]
     ring2 = ring_for_nodes(nodes)
     res1_set = @test_set |> map(fn k -> {k,node_for_key(key_as_int(k),ring)} end) 
     res2_set = @test_set |> map(fn k -> {k,node_for_key(key_as_int(k),ring2)} end) 
     IO.puts inspect Set.difference(res1_set|>HashSet.new,res2_set|>HashSet.new) |> Set.size
    
  #  chash_ring = chash_ring(@nodes)
  #  IO.puts inspect chash_ring
  #  chash_res_set = @test_set |> map(fn k -> {k,:chash.successors(:chash.key_of(k),chash_ring,1) |> at(0) |> elem(1)} end) |> HashSet.new
  #  chash_ring2 = chash_ring(nodes)
  #  chash_res_set2 = @test_set |> Enum.map(fn k -> {k,:chash.successors(:chash.key_of(k),chash_ring2,1) |> at(0) |> elem(1)} end) |> HashSet.new
  #  IO.puts inspect Set.difference(chash_res_set,chash_res_set2) |> Set.size
  end

  #defp chash_ring2(nodes) do
  #  ring = :chash.fresh(64, :n1)
  #  nodes |> with_index 
  #        |> map(fn {n,i}->{ring|>:chash.nodes|>slice(i,64)|>take_every(length(nodes)),i} end) 
  #        |> reduce(ring,
  #             fn {partitions,node_index},ring1 ->
  #               partitions |> reduce(ring1,fn {idx,_},ring2 ->
  #                 :chash.update(idx,at(nodes,node_index),ring2)
  #               end)
  #             end)
  #end
  #defp chash_ring3(nodes) do
  #  ring = :chash.fresh(64, :n1)
  #  ring |> :chash.nodes
  #       |> chunks(div(64,length(nodes)),div(64,length(nodes)),[]) 
  #       |> with_index
  #       |> reduce(ring,
  #            fn {partitions,node_index},ring1 ->
  #              partitions |> reduce(ring1,fn {idx,_},ring2 ->
  #                :chash.update(idx,at(nodes,node_index),ring2)
  #              end)
  #            end)
  #end
  #defp chash_ring(nodes) do
  #  nb_rep = 20
  #  ring = :chash.fresh((length(nodes))*nb_rep, :n1)
  #  nodes |> map(fn n -> {n,1..nb_rep |> map &"#{n}#{&1}"} end)
  #        |> reduce(ring,
  #            fn {node,replicates},ring1 ->
  #              replicates |> reduce(ring1,fn rep_name,ring2 ->
  #                :chash.update(:chash.successors(:chash.key_of(rep_name),ring2,1) |> at(0) |> elem(0),node,ring2)
  #              end)
  #            end)
  #end
  #defp chash_ring(nodes) do
  #  ring = :chash.fresh(64, :n1)
  #  nodes |> map(fn n->{n,:chash.successors(:chash.key_of(n),ring)|>take_every(length(nodes))} end) 
  #        |> reduce(ring,
  #             fn {node,replicates},ring1 ->
  #               replicates |> reduce(ring1,fn {idx,_},ring2 ->
  #                 :chash.update(idx,node,ring2)
  #               end)
  #             end)
  #end
end
