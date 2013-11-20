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

The different hashes are inserted into a dedicated binary search
tree to optimize the node lookups.



    nano_ring -> nodes_event_manager
              -> nodes_manager
    supervisorring -> ring_event_manager
                   -> super_sup
                   -> handler_restarter -> ring_manager(nodes_event_handler)
    your_app -> your_sup_tree -> :supervisorring.start_link(XXX,yoursupmodule)
    ====
    your_app -> your_sup_tree -> global_sup -> local_sup(children=global_children |> filter(ConsistentHash.node_for_key(child.id)==node()))
                                            -> global_sup_manager -> local_sup_manager(ring_event_handler)

The chain of processes `global_sup -> local_sup -> children` is used to supervise children so that :
- if a child die it is restarted by `local_sup` as a classical supervised process
- if the child die repeatedly (according to defined MaxR,MaxT), `local_sup` will die
- if `local_sup` die, it is restarted by `global_sup` to "test" if
  local children state restoration is sufficient to ensure the viability
  of the children
- if `local_sup` die, repeatedly, according to MaxR=2 MaxT=`LocalMaxT*2`,
  then `global_sup` will die
- `super_sup` is linked to `global_sup` and trap exit so that when
 `global_sup` exits for anormal reason, it send `exit(global_sup_ref,normal)` 
  to all nodes in order to kill the supervisor "globally" (as the
  supervisor maintains the list of children globally, the working child
  state may need a global children restart)

The way children supervised by `supervisorring` can be supervised
globally in a similar fashion as `local_supervision` locally.

## How to test Supervisorring ##

