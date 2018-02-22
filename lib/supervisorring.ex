defmodule Supervisorring do
  @moduledoc """
  A cluster wide supervisor

  This module is an Elixir-friendly wrapper for `:supervisorring`
  (erlang-friendly) module.
  """

  @doc false
  defmacro __using__(_) do
    quote do
      @behaviour :dyn_child_handler
      @behaviour :supervisorring
      import Supervisor.Spec

      def migrate(_,_,_), do: :ok

      def match(_), do: true
      def get_all, do: []
      def add(_), do: :ok
      def del(_), do: :ok

      def dynamic, do: {:dyn_child_handler, __MODULE__}

      defoverridable [match: 1, get_all: 0, add: 1, del: 1, migrate: 3]
    end
  end

  @doc false
  def start_link(module, arg, name: name) when is_atom(name) do
    :supervisorring.start_link({:local, name}, module, arg)
  end

  defdelegate find(supref, id), to: :supervisorring
  defdelegate exec(supref, id, fun, timeout, retry), to: :supervisorring
  defdelegate exec(supref, id, fun, timeout), to: :supervisorring
  defdelegate exec(supref, id, fun), to: :supervisorring
  defdelegate start_child(supref, spec), to: :supervisorring
  defdelegate terminate_child(supref, id), to: :supervisorring
  defdelegate delete_child(supref, id), to: :supervisorring
  defdelegate restart_child(supref, id), to: :supervisorring
  defdelegate which_children(supref), to: :supervisorring
  defdelegate count_children(supref), to: :supervisorring

  @doc false
  def global_sup_ref(sup_ref), do: :"#{sup_ref}.GlobalSup"

  @doc false
  def child_manager_ref(sup_ref), do: :"#{sup_ref}.ChildManager"

  @doc false
  def local_sup_ref(sup_ref), do: sup_ref
end

defmodule :supervisorring do
  @moduledoc """
  A cluster wide supervisor.

  If using from Elixir, you will prefer `Supervisorring` module
  """

  @doc """
  Process migration function, called before deleting a pid when the ring change
  """
  @callback migrate({id :: atom, type :: :worker |:supervisor, modules :: [ module ] | :dynamic }, old_pid :: pid,new_pid :: pid) :: any
  
  @doc """
  Supervisor standard callback, but with a new type of childspec to handle an
  external (global) source of child list (necessary for dynamic child starts,
  global process list must be maintained externally):
  - standard child_spec : {id,startFunc,restart,shutdown,type,modules}
  - new child_spec : {:dyn_child_handler,module::dyn_child_handler}
  works only with :permanent children, because a terminate state is restarted on ring migration
  """
  @callback init(args::term) :: any

  @doc """
  Find node is fast but rely on local ring
  """
  @spec find(atom, atom) :: atom
  def find(supref, id) do
    GenServer.call(Supervisorring.child_manager_ref(supref), {:get_node, id})
  end
  
  @doc """
  exec() remotely queued execution to ensure reliability even if a node of the
  ring has just crashed... with nb_try retry if timeout is reached
  """
  def exec(supref,id,fun,timeout \\ 30_000,retry \\ 3) do
    try_exec(Supervisorring.child_manager_ref(supref),id,fun,timeout,retry)
  end
  
  @doc """
  Start supervisorring process, which is a simple erlang supervisor,
  but the children are dynamically defined as the processes whose "id"
  is mapped to the current node in the ring. An event handler kills or
  starts children on ring change if necessary to maintain the proper
  process distribution.
  """
  @spec start_link({:local, atom}, module, term) :: Supervisor.on_start
  def start_link({:local, name}, module, args) do
    Supervisorring.GlobalSup.start_link(name,{module,args})
  end

  @doc """ 
  To maintain global process list related to a given
  {:child_spec_gen, fun} external child list specification
  """
  @spec start_child(atom, :supervisor.child_spec()) :: Supervisor.on_start_child
  def start_child(supref, {id, _, _, _, _, _}=childspec) do
    ret = exec(supref, id, fn ->
      Supervisor.start_child(Supervisorring.local_sup_ref(supref), childspec)
    end)
    case ret do
      {:ok, child}->
	ref = make_ref()
        GenServer.cast(Supervisorring.child_manager_ref(supref), {:get_handler, id, {self(), ref}})
        receive do
          {^ref, {:dyn_child_handler, handler}} ->
	    {handler.add(childspec), child}
          {^ref, _} ->
	    {:error, {:cannot_match_handler, id}}
        after
	  10000 ->
	    {:error, :child_server_timeout}
        end
      r -> r
    end
  end

  @doc """
  Terminate the given children
  """
  @spec terminate_child(Supervisor.supervisor, pid) :: :ok | {:error, :not_found | :simple_one_for_one}
  def terminate_child(supref, id) do
    exec(supref, id, fn ->
      Supervisor.terminate_child(Supervisorring.local_sup_ref(supref), id)
    end)
  end

  @doc """
  To maintain global process list related to a given
  {:child_spec_gen, fun} external child list specification
  """
  @spec delete_child(Supervisor.supervisor, pid) :: :ok | {:error, :not_found | :simple_one_for_one}
  def delete_child(supref, id) do
    ret = exec(supref, id, fn ->
      Supervisor.delete_child(Supervisorring.local_sup_ref(supref), id)
    end)
    case ret do
      :ok ->
        ref = make_ref()
        GenServer.cast(Supervisorring.child_manager_ref(supref), {:get_handler, id, {self(), ref}})
        receive do
          {^ref, {:dyn_child_handler, handler}} ->
	    handler.del(id)
          {^ref, _} ->
	    {:error, {:cannot_match_handler, id}}
        after
	  10000 ->
	    {:error, :child_server_timeout}
        end
      r -> r
    end
  end

  @doc """
  Restart given child
  """
  @spec restart_child(Supervisor.supervisor, pid) ::
    {:ok, pid} |
    {:ok, pid, term} |
    {:error, error} when error: :not_found | :simple_one_for_one | :running | :restarting | term
  def restart_child(supref, id) do
      exec(supref, id, fn ->
	Supervisor.restart_child(Supervisorring.local_sup_ref(supref), id)
      end)
  end

  @doc """
  Returns list with informations about all children
  """
  @spec which_children(Supervisor.supervisor) :: []
  def which_children(supref) do
    {res, _} = :rpc.multicall(Enum.to_list(NanoRing.up()),
      Supervisor, :which_children, [Supervisorring.local_sup_ref(supref)])
    Enum.concat(res)
  end

  @doc """
  Returns number of children
  """
  @spec count_children(Supervisor.supervisor) :: integer
  def count_children(supref) do
    {res, _} = :rpc.multicall(Enum.to_list(NanoRing.up()),
      Supervisor, :count_children, [Supervisorring.local_sup_ref(supref)])
    Enum.reduce(res, [], fn(statdict, acc) ->
      Map.merge(acc, statdict, fn _, v1, v2 -> v1 + v2 end)
    end)
  end

  ###
  ### Priv
  ###
  defp try_exec(_, _, _, _, 0), do: exit(:ring_unable_to_exec_fun)
  defp try_exec(child_manager, id, fun, timeout, nb_try) do
    ref = make_ref()
    GenServer.cast child_manager, {:onnode, id, {self(), ref}, fun}
    receive do
      {^ref, :executed,res} -> res
    after
      timeout -> try_exec(child_manager, id, fun, timeout, nb_try-1) end
    end
end

