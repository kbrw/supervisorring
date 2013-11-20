defmodule Supervisorring do
  def global_sup_ref(sup_ref), do: "#{sup_ref}_global_sup"
  def child_manager_ref(sup_ref), do: "#{sup_ref}_child_manager"
  def local_sup_ref(sup_ref), do: supref

  defmodule GlobalSup do
    use Supervisor.Behaviour
    def start_link(sup_ref,module_args), do:
      :supervisor.start_link({:local,sup_ref|>Supervisorring.global_sup_ref},__MODULE__,{sup_ref,module_args})
    def init({sup_ref,{module,args}}) do
      {:ok,{strategy,specs}}=module.init(args)
      Process.link(Process.whereis(Supervisorring.App.Sup.SuperSup))
      supervise([
        supervisor(GlobalSup.LocalSup,[sup_ref,strategy]),
        worker(GlobalSup.ChildManager,[sup_ref,specs,module])
      ], strategy: :one_for_all) #Nodes Workers are bounded to directory manager
    end
    defmodule LocalSup do
      use Supervisor.Behaviour
      def start_link(sup_ref,strategy), do: 
        :supervisor.start_link({:local,sup_ref|>Supervisorring.local_sup_ref},__MODULE__,strategy)
      def init(strategy), do: {:ok,{strategy,[]}}
    end
    defmodule ChildManager do
      use GenServer.Behaviour
      import Enum
      defrecord State, sup_ref: nil, child_specs: [], callback: nil
      defmodule RingListener do
        use GenEvent.Behaviour
        def handle_event(:new_ring,child_manager) do
          :gen_server.cast(child_manager,:sync_children)
          {:ok,child_manager}
        end
      end

      def start_link(sup_ref,specs,callback), do:
        :supervisor.start_link({:local,sup_ref|>Supervisorring.child_manager_ref},__MODULE__,{sup_ref,specs,callback})
      def init({sup_ref,child_specs,callback}), do:
        handle_cast(:sync_children,State[sup_ref: sup_ref,child_specs: specs,callback: callback])
      def handle_cast(:sync_children,State[sup_ref: sup_ref,child_specs: specs,callback: callback]=state) do
        ring = :gen_event.call(Supervisorring.Server.RingListener,:get_ring)
        cur_children = :supervisor.which_children(sup_ref|>Supervisorring.local_sup_ref) |> reduce(HashDict.new,fn {id,_,_,_}=e,dic->dic|>Dict.put(id,e) end)
        wanted_children = expand_specs(specs)|>filter(fn {id,_,_,_}->(ring|>ConsistentHash.node_for_key(id)) == node() end)
                                           |>reduce(HashDict.new,fn {id,_,_,_,_,_}=e,dic->dic|>Dict.put(id,e) end)
        cur_children |> filter(&not(Dict.has_key?(wanted_children,&1))) |> each fn {id,child,type,modules}->
          case child do
            :undefined ->
            :restarted ->
            oldpid ->
              {:already_started,newpid} = :rpc.call(ring|>ConsistentHash.node_for_key(id),
                :supervisor,:start_child,[sup_ref|>Supervisorring.local_sup_ref,wanted_children|>Dict.get(id)])
              callback.migrate({id,type,modules},oldpid,newpid)
              sup_ref |> Supervisorring.local_sup_ref |> :supervisor.terminate_child(id)
              sup_ref |> Supervisorring.local_sup_ref |> :supervisor.delete_child(id)
          end
        end
        wanted_children |> filter(&not(Dict.has_key?(cur_children,&1)) |> each fn childspec-> 
          :supervisor.start_child(sup_ref|>Supervisorring.local_sup_ref,childspec)
        end
        state
      end
      defp expand_specs(specs) do
        {child_specs,spec_generators} = specs |> partition &is_tuple
        concat(child_specs,spec_generators |> flat_map &(&1()))
      end
    end
  end
end

defmodule :supervisorring do
  use Behaviour
  import Supervisorring
  @doc "process migration function, called before deleting a pid when the ring change"
  defcallback migrate({id,type,modules},old_pid,new_pid)
  @doc """
  callback called when a child has been started dynamically, should be used to
  maintain the global lists of processes returned by every {:child_spec_gen,fun}
  """
  defcallback save_child(child_spec)
  @doc """
  supervisor standard callback, but with a new type of childspec to handle an
  external (global) source of child list (necessary for dynamic child starts,
  global process list must be maintained externally):
  standard child_spec : {id,startFunc,restart,shutdown,type,modules}
  new child_spec : {:child_spec_gen,fun()->[:standard_child_spec]}
  """
  defcallback init(args)

  @doc """
  start supervisorring process, which is a simple erlang supervisor, but the
  children are dynamically defined as the processes whose "id" is mapped to the
  current node in the ring. An event handler kills or starts children on ring
  change if necessary to maintain the proper process distribution.
  """
  def start_link(name,module,args), do:
    :supervisor.start_link(name,Supervisorring.Sup,{name,module,args})

  def start_child(supref,childspec) do
    rpc.call(:gen_event.call({Supervisorring.ChildManager,sup_ref},:get_ring)|>ConsistentHash.node_for_key(id),
        :supervisor,:start_child,[sup_ref|>local_sup_ref,childspec])
  end

  def terminate_child(supref,id) do
    rpc.call(:gen_event.call({Supervisorring.ChildManager,sup_ref},:get_ring)|>ConsistentHash.node_for_key(id),
       :supervisor,:terminate_child,[sup_ref|>local_sup_ref,id])
  end

  def restart_child(supref,id) do
    rpc.call(:gen_event.call({Supervisorring.ChildManager,sup_ref},:get_ring)|>ConsistentHash.node_for_key(id),
       :supervisor,:restart_child,[sup_ref|>local_sup_ref,id])
  end

  def which_children(supref) do
    
  end

  def count_children(supref) do
    
  end
end

