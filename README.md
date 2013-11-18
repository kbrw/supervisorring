supervisorring
==============

Supervisorring is a small Elixir library and behaviour to create a
distributed `gen_server`.

## TODO ##

Make it work.

## How does it work ? ##

`supervisorring` uses `nano_ring` (
        https://github.com/awetzel/nano_ring ) to be kept updated of
the cluster nodes.

A distributed hash table distribute servers to the different nodes.
The nodes are itself placed on the same dht with the hash of the node
name, so that a small number of servers are redistribute on the
addition or removal of a node (consistent hashing).

The differents hashes are inserted into a dedicated binary search
tree to optimize the node lookups.

## How to test Supervisorring ##


