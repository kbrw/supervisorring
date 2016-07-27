supervisorring
==============

Supervisorring exposes the same module and behaviour as an erlang OTP supervisor but
distributed into several nodes monitored using (https://github.com/awetzel/nano_ring ):
- each child is started on different up nodes according to the mapping of the
  child id on a consistent hashing DHT
- when the up node cluster change (NanoRing event), on each node, according to
  the new DHT : moved in processes are started, moved out processes are killed,
  and a state migration happened before the kill if possible
- when child die repeatedly, a local supervisor is restarted to try a local
  state restoration, if this local supervisor die repeatedly, then
  all the supervisors on all nodes are killed , then let the parent
  supervisor of the supervisorring supervisor handle the global state
  restoration (like with a classical otp supervisor)

## Usage ##

The `supervisorring` module and behaviour can be use nearly the same way as the
OTP/erlang :supervisor module and behaviour with the following differences :
- `terminate_child` only stops child locally, if the child is moved on another
  node then a terminated child will be restarted.
- children cannot be `transient` or `temporary`, they have to be `permanent`
  for the reason above.
- children are not necessary started in the given order.
- the supervisor has to have locally registered name, so the `start_link/2`
  does not exist and `start_link/3` needs {:local,NAME} as first parameter.
- in addition to the supervisor `init/1` function, :supervisorring behaviour
  needs you to implement a `migrate/3` function which will be called if
  possible before to kill a child on a node where it doesnot belong anymore.
- in order to allow the use of dynamic child management (`start_child /delete_child`), 
  you need to maintain a global list of children. To allow that, a new
  `child_spec` can be used in `init/1` child list : `{:dyn_child_handler,YourModule}`.
  `YourModule` has to implement the behaviour `:dyn_child_handler` :
  - `add(::childspec)->:ok,del(::childid)->:ok` callbacks will be used
     respectively after a successful `start_child` and `delete_child`
  - `get_all()->[::childspec]` callback will be called during ring migration in
     order to get the current global list of children to determine which one
     has to be started locally.
  - `match(::childid)->boolean` allows you to use multiple `:dyn_child_handler`
     in childspecs and during addition and deletion, the correct handler will be
     selected if the child id match according to this function.
- in addition to supervisor function, supervisorring exposes two necessary new functions :
  - `find(supname,childid)` allows you to find the node where a child belong. Indeed, 
     as a supervisor, a supervisorring does not give you a particular way to locate
     your process among its children, you have to use your own mechanism to locate
     your process : register, pid communication, etc... BUT if you just use
     locally registered pid, you need to know the node where the child run for
     instance if the registered name is also the child id in sup :
     `:gen_server.call({ChildName,:supervisorring.find(ChildSup,ChildName)},:you_call)`
  - the local ring may be unaware of the last ring update and
    :supervisorring.find can give you a down node if this one just crashed. To
    ensure that your code executes himself on the node where a given child
    is currently running, you can use `exec(supname,childid,youfun)` 
- finally, the local supervisor is registered with the name given to the
  supervisorring, so you can use for instance :
  `:supervisorring.which_children(MySup)` to get all the children of the distributed supervisor and
  `:supervisor.which_children(MySup)` to get the local children associate with this supervisor.

The `:dyn_child_handler` can maintain the child list globally with an external
database shared by every cluster nodes (network fs,mnesia,riak,etc.).

Example : 

```elixir
defmodule MySup do
  use :supervisorring
	import Supervisor.spec

  def migrate({_id,_type,_modules},old_server,new_server), do:
    :gen_server.cast(new_server,{:set_state,:gen_server.call(old_server,:get_state)})

  def init(_arg) do
    {:ok,{{:one_for_one,2,3},[
      {:dyn_child_handler,NetFSChildHandler},
      worker(GenServer, [GenericServer, nil], id: MySup.C1),
      worker(GenServer, [GenericServer, nil], id: MySup.C2)
    ]}}
  end
end

defmodule GenericServer do
  use GenServer
  def handle_call(:get, _, s), do: {:reply, s, s}
  def handle_cast(new_state, _), do: {:noreply, new_state}
end

# if childs file is shared on every node with a shared fs :
defmodule NetFSChildHandler do
  @behaviour :dyn_child_handler
  def match(_), do: true
  def get_all, do:
    File.read!("childs")|>binary_to_term
  def add(childspec), do:
    File.write!("childs",File.read!("childs") |> binary_to_term |> List.insert_at(0,childspec) |> term_to_binary)
  def del(childid), do:
    File.write!("childs",File.read!("childs") |> binary_to_term |> List.keydelete(childid,0) |> term_to_binary)
end

:supervisorring.start_link({:local,MySup},MySup,nil)
import Supervisor.Spec
c3 = worker(GenServer, [GenericServer, nil], id: MySup.C3)
:supervisorring.start_child(MySup,c3)
:gen_server.cast({MySup.C3,:supervisorring.find(MySup,MySup.C3)},:youcall)
:gen_server.call({MySup.C3,:supervisorring.find(MySup,MySup.C3)},:get)
# get all childs
:supervisorring.which_children(MySup)
# get local childs
:supervisor.which_children(MySup)
```

## How does it work ? ##

    Supervisorring.App.Sup-> .Events
                          -> .SuperSup -> NodesListener
    your_app -> your_sup_tree -> your_supervisorring -> your_childs
    actually starts the following supervision tree :
    your_app -> your_sup_tree -> global_sup -> local_sup(children=your_childs in dht(localnode)))
                                            -> child_manager -> ring_event_handler

The application `SuperSup gen_server` listens nanoring events to
update its consistant hashing dht, then notify all the local
Supervisiorring Global Supervisor with a `gen_event`.

The `ChildManager gen_server` start or kill the local supervisor
children according to the new DHT.

The local children are supervised by 2 parent supervisor, `global_sup ->
local_sup -> children` so that :
- if a child die it is restarted by `local_sup` as a classical supervised process
- if the child die repeatedly (according to defined MaxR,MaxT), `local_sup` will die
- if `local_sup` die, it is restarted by `global_sup` to "test" if
  local children state restoration is sufficient to ensure the viability
  of the children
- if `local_sup` die, repeatedly, according to MaxR=2 MaxT=`LocalMaxT*2`,
  then `global_sup` will die
- `super_sup` monitors `global_sup` so that when `global_sup` exits for anormal
   reason, it send `exit(global_sup_ref,kill)` to all nodes in order to kill the
   supervisor "globally" (as the supervisor maintains the list of children
   globally, the working child state may need a global children restart)

This way children supervised by `supervisorring` can be supervised
globally in a similar fashion as `local_supervision` locally.

