defmodule Supervisorring do

  def global_sup_ref(sup_ref), do: :"#{sup_ref}.GlobalSup"

  def child_manager_ref(sup_ref), do: :"#{sup_ref}.ChildManager"

  def local_sup_ref(sup_ref), do: sup_ref

  defmodule GlobalSup do
    use Supervisor

    def start_link(sup_ref, module_args), do:
      Supervisor.start_link(__MODULE__, {sup_ref, module_args},
        name: sup_ref |> Supervisorring.global_sup_ref)

    def init({sup_ref, {module, args}}) do
      {:ok, {strategy, specs}} = module.init(args)
      GenServer.cast(Supervisorring.App.Sup.SuperSup,
        {:monitor, sup_ref |> Supervisorring.global_sup_ref})
      children =
        [supervisor(GlobalSup.LocalSup, [sup_ref, strategy]),
         worker(GlobalSup.ChildManager, [sup_ref, specs, module])]
      #Nodes Workers are bounded to directory manager
      supervise(children, strategy: :one_for_all)
    end

    defmodule LocalSup do
      use Supervisor

      def start_link(sup_ref, strategy), do:
        Supervisor.start_link(__MODULE__, strategy,
          name: Supervisorring.local_sup_ref(sup_ref))

      def init(strategy), do: {:ok, {strategy, []}}
    end

    defmodule ChildManager do
      use GenServer
      import Enum

      defmodule State do
        defstruct(sup_ref: nil, child_specs: [], callback: nil, ring: nil)
      end

      defmodule RingListener do
        use GenEvent

        def handle_event({:new_ring, _reason}, child_manager) do
          GenServer.cast(child_manager, :sync_children)
          {:ok, child_manager}
        end

      end

      def start_link(sup_ref, specs, callback) do
        GenServer.start_link(__MODULE__, {sup_ref, specs, callback},
          name: sup_ref |> Supervisorring.child_manager_ref)
      end

      def init({sup_ref, child_specs, callback}) do
        :gen_event.add_sup_handler(Supervisorring.Events, RingListener, self)
        state =
          %State{sup_ref: sup_ref, child_specs: child_specs, callback: callback}
        {:noreply, state} = handle_cast(:sync_children, state)
        {:ok, state}
      end

      def handle_info({:gen_event_EXIT, _, _}, _), do: exit(:ring_listener_died)

      def handle_call({:get_node, id}, _, state) do
        reply = ConsistentHash.node_for_key(state.ring, {state.sup_ref, id})
        {:reply, reply, state}
      end

      # reliable execution is ensured by queueing executions on the same queue
      # which modify local children according to ring (on :sync_children
      # message) so if "node_for_key" == node then proc associated with id is
      # running on the node
      def handle_cast({:onnode, id, {sender, ref}, fun}, state) do
        case ConsistentHash.node_for_key(state.ring, {state.sup_ref, id}) do
          n when n == node -> send sender, {ref, :executed, fun.()}
          othernode ->
            GenServer.cast(
              {state.sup_ref |> Supervisorring.child_manager_ref, othernode},
              {:onnode, id, {sender, ref}, fun}
            )
        end
        {:noreply, state}
      end
      def handle_cast({:get_handler, childid, {sender, ref}}, state) do
        handler =
          state.child_specs
          |> filter(&match?({:dyn_child_handler, _}, &1))
          |> find(fn{_, h} -> h.match(childid) end)
        send(sender, {ref, handler})
        {:noreply, state}
      end
      def handle_cast(:sync_children, %State{sup_ref: sup_ref} = state) do
        ring = GenServer.call(DHTGenServer, :get_ring)
        cur_children = cur_children(sup_ref)
        wanted_children = wanted_children(state, ring)

        migrate_fun =
          fn(child_spec) -> migrate_child(child_spec, ring, state) end
        cur_children
        |> filter(fn {id, _} -> not Dict.has_key?(wanted_children, id) end)
        |> each(migrate_fun)

        start_fun =
          fn {_, childspec} ->
            Supervisor.start_child(Supervisorring.local_sup_ref(sup_ref),
              childspec)
          end
        wanted_children
        |> filter(fn {id, _} -> not Dict.has_key?(cur_children, id) end)
        |> each(start_fun)

        {:noreply, %{state | ring: ring}}
      end

      defp cur_children(sup_ref) do
        fun = fn ({id, _, _, _} = e, dic) -> dic |> Dict.put(id, e) end
        Supervisor.which_children(Supervisorring.local_sup_ref(sup_ref))
        |> reduce(HashDict.new, fun)
      end

      ## the tricky point is here, take only child specs with an id which is
      ## associated with the current node in the ring
      defp wanted_children(state, ring) do
        %State{sup_ref: sup_ref, child_specs: specs} = state
        all_children = all_children(specs)
        remote_children_keys =
          all_children
          |> Dict.keys
          |> filter(&(ConsistentHash.node_for_key(ring,{sup_ref,&1}) !== node))
        all_children |> Dict.drop(remote_children_keys)
      end

      defp all_children(specs) do
        fun = fn({id, _, _, _, _, _} = e, dic) -> dic |> Dict.put(id, e) end
        expand_specs(specs) |> reduce(HashDict.new, fun)
      end

      defp expand_specs(specs) do
        {spec_generators, child_specs} =
          specs |> partition(&match?({:dyn_child_handler, _}, &1))
        concat(child_specs,
          spec_generators
          |> flat_map(fn {:dyn_child_handler, handler} -> handler.get_all end))
      end

      ## kill all the local children which should not be in the node,
      ## get/start child on the correct node to migrate state if needed
      defp migrate_child({id, {id, child, type, modules}}, ring, state) do
        %State{sup_ref: sup_ref, child_specs: specs, callback: callback} = state
        new_node = ConsistentHash.node_for_key(ring, {sup_ref, id})
        if is_pid(child) do
          rpc_args =
            [Supervisorring.local_sup_ref(sup_ref),
              specs |> all_children |> Dict.get(id)]
          is_started = :rpc.call(new_node, Supervisor, :start_child, rpc_args)
          case is_started do
            {:error, {:already_started, existingpid}} ->
              callback.migrate({id, type, modules}, child, existingpid)
            {:ok, newpid} ->
              callback.migrate({id, type, modules}, child, newpid)
            _ -> :nothingtodo
          end
          sup_ref
          |> Supervisorring.local_sup_ref
          |> Supervisor.terminate_child(id)
        end
        sup_ref |> Supervisorring.local_sup_ref |> Supervisor.delete_child(id)
      end

    end
  end

  defmacro __using__(_) do
    quote do
      @behaviour :dyn_child_handler
      @behaviour :supervisorring
      import Supervisor.Spec

      def migrate(_, _, _), do: :ok

      def match(_), do: true
      def get_all, do: []
      def add(_), do: :ok
      def del(_), do: :ok

      def dynamic, do: {:dyn_child_handler, __MODULE__}

      defoverridable [match: 1, get_all: 0, add: 1, del: 1, migrate: 3]
    end
  end

  def start_link(module, arg, name: name) when is_atom(name) do
    :supervisorring.start_link({:local, name}, module, arg)
  end

  defdelegate [find(supref, id),
               exec(supref, id, fun, timeout, retry),
               exec(supref, id, fun, timeout),
               exec(supref, id, fun),
               start_child(supref, spec),
               terminate_child(supref, id),
               delete_child(supref, id),
               restart_child(supref, id),
               which_children(supref),
               count_children(supref)], to: :supervisorring
end

defmodule :dyn_child_handler do
  use Behaviour
  defcallback get_all
  defcallback match(child_id::atom())
  defcallback add(child_spec :: term())
  defcallback del(child_id :: atom())
end

defmodule :supervisorring do
  use Behaviour

  @doc "process migration function, called before deleting a pid when the ring change"
  defcallback migrate({id::atom(),type:: :worker|:supervisor, modules::[module()]|:dynamic},old_pid::pid(),new_pid::pid())
  @doc """
  supervisor standard callback, but with a new type of childspec to handle an
  external (global) source of child list (necessary for dynamic child starts,
  global process list must be maintained externally):
  standard child_spec : {id, startFunc, restart, shutdown, type, modules}
  new child_spec : {:dyn_child_handler, module::dyn_child_handler}
  works only with :permanent children, because a terminate state is restarted on
  ring migration
  """
  defcallback init(args::term())

  @doc "find node is fast but rely on local ring"
  def find(supref, id) do
    GenServer.call(Supervisorring.child_manager_ref(supref), {:get_node, id})
  end
  @doc """
  exec() remotely queued execution to ensure reliability even if a node of the
  ring has just crashed... with nb_try retry if timeout is reached
  """
  def exec(supref, id, fun, timeout \\ 1000, retry \\ 3), do:
    try_exec(Supervisorring.child_manager_ref(supref), id, fun, timeout, retry)
  def try_exec(_, _, _, _, 0), do: exit(:ring_unable_to_exec_fun)
  def try_exec(child_manager, id, fun, timeout, nb_try) do
    ref = make_ref
    GenServer.cast child_manager, {:onnode, id, {self, ref}, fun}
    receive do
      {^ref, :executed, res} -> res
      after timeout -> try_exec(child_manager, id, fun, timeout, nb_try - 1)
    end
  end

  @doc """
  start supervisorring process, which is a simple erlang supervisor, but the
  children are dynamically defined as the processes whose "id" is mapped to the
  current node in the ring. An event handler kills or starts children on ring
  change if necessary to maintain the proper process distribution.
  """
  def start_link({:local, name}, module, args),
    do: Supervisorring.GlobalSup.start_link(name, {module, args})

  @doc """
  to maintain global process list related to a given {:child_spec_gen, fun}
  external child list specification
  """
  def start_child(supref, {id, _, _, _, _, _} = childspec) do
    fun =
      fn ->
        Supervisor.start_child(Supervisorring.local_sup_ref(supref), childspec)
      end
IO.puts("#{:erlang.system_time} #{node} start_child #{id}")
    case exec(supref, id, fun) do
      {:ok, child} -> ref = make_ref
        GenServer.cast(Supervisorring.child_manager_ref(supref),
          {:get_handler, id, {self, ref}})
        receive do
          {^ref, {:dyn_child_handler,handler}} -> {handler.add(childspec),child}
          {^ref, _} -> {:error, {:cannot_match_handler, id}}
          after 10000 -> {:error, :child_server_timeout}
        end
      r -> r
    end
  end

  def terminate_child(supref, id) do
    fun =
      fn -> Supervisor.terminate_child(Supervisorring.local_sup_ref(supref), id)
    end
    exec(supref, id, fun)
  end

  @doc """
  to maintain global process list related to a given {:child_spec_gen, fun}
  external child list specification
  """
  def delete_child(supref, id) do
    fun =
      fn ->
        Supervisor.delete_child(Supervisorring.local_sup_ref(supref), id)
      end
    case exec(supref, id, fun) do
      :ok ->
        ref = make_ref
        GenServer.cast(Supervisorring.child_manager_ref(supref),
          {:get_handler, id, {self, ref}})
        receive do
          {^ref, {:dyn_child_handler, handler}} -> handler.del(id)
          {^ref, _} -> {:error, {:cannot_match_handler, id}}
          after 10000 -> {:error, :child_server_timeout}
        end
      r -> r
    end
  end

  def restart_child(supref, id) do
    fun =
      fn ->
        Supervisor.restart_child(Supervisorring.local_sup_ref(supref), id)
      end
    exec(supref, id, fun)
  end

  def which_children(supref) do
    ring_name = Supervisorring.App.Sup.SuperSup.ring_name()
    {res, _} =
      :rpc.multicall(
        GenServer.call(ring_name, :get_up) |> Enum.to_list,
        Supervisor,
        :which_children,
        [Supervisorring.local_sup_ref(supref)]
      )
    res |> Enum.concat
  end

  def count_children(supref) do
    ring_name = Supervisorring.App.Sup.SuperSup.ring_name()
    {res, _} =
      :rpc.multicall(
        GenServer.call(ring_name, :get_up) |> Enum.to_list,
        Supervisor,
        :count_children,
        [Supervisorring.local_sup_ref(supref)]
      )
    fun =
      fn (dict, acc) -> acc |> Dict.merge(dict, fn _, v1, v2 -> v1 + v2 end) end
    res |> Enum.reduce([], fun)
  end
end

