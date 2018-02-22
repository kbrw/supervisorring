defmodule Supervisorring.ChildManager do
  @moduledoc """
  Manage local supervisor children according to cluster changes.
  """
  use GenServer

  defmodule State do
    @moduledoc """
    Defines structure used by ChildManager
    """
    defstruct sup_ref: nil, child_specs: [], callback: nil, ring: nil

    @type t :: %__MODULE__{}
  end
  
  defmodule RingListener do
    @moduledoc """
    Notifies ChildManager about cluster changes
    """
    use GenEvent
    
    def handle_event(:new_ring, child_manager) do
      GenServer.cast(child_manager, :sync_children)
      {:ok, child_manager}
    end
  end

  @doc """
  Start child manager
  """
  @spec start_link(atom, [Supervisor.child_spec()], fun) :: GenServer.on_start
  def start_link(sup_ref, specs, callback) do
    GenServer.start_link(__MODULE__, {sup_ref, specs, callback},
      name: Supervisorring.child_manager_ref(sup_ref))
  end

  ###
  ### GenServer callbacks
  ###
  @doc false
  def init({sup_ref, child_specs, callback}) do
    :gen_event.add_sup_handler(Supervisorring.Events,RingListener, self())
    
    {:noreply, state} = handle_cast(:sync_children,
      %State{sup_ref: sup_ref, child_specs: child_specs, callback: callback})
    {:ok, state}
  end

  @doc false
  def handle_info({:gen_event_EXIT, _, _}, _) do
    exit(:ring_listener_died)
  end

  @doc false
  def handle_call({:get_node, id}, _, state) do
    {:reply, ConsistentHash.get_node(state.ring, {state.sup_ref, id}), state}
  end

  # reliable execution is ensured by queueing executions on the same queue
  # which modify local children according to ring (on :sync_children message) so if
  # "get_node"==node then proc associated with id is running on the node
  @doc false
  def handle_cast({:onnode, id, {sender, ref}, fun}, state) do
    case ConsistentHash.get_node(state.ring, {state.sup_ref, id}) do
      n when n==node() ->
	send sender, {ref, :executed, fun.()}
      othernode ->
	GenServer.cast({Supervisorring.child_manager_ref(state.sup_ref), othernode},
	  {:onnode, id, {sender, ref}, fun})
    end
    {:noreply, state}
  end
  def handle_cast({:get_handler, childid, {sender, ref}}, %State{child_specs: specs}=state) do
    child_spec = Enum.filter(specs, &match?({:dyn_child_handler, _}, &1)) |>
      Enum.find(fn {_, h} ->
	h.match(childid)
      end)
    send sender, {ref, child_spec}
    {:noreply, state}
  end
  def handle_cast(:sync_children, %State{sup_ref: sup_ref, child_specs: specs, callback: callback}=state) do
    ring = :gen_event.call(NanoRing.Events, Supervisorring.NodesListener, :get_ring)

    cur_children = Supervisor.which_children(Supervisorring.local_sup_ref(sup_ref)) |>
      Enum.reduce(Map.new(),fn {id, _, _, _}=e, acc -> Map.put(acc, id, e) end)
    all_children = expand_specs(specs) |>
      Enum.reduce(Map.new(), fn {id, _, _, _, _, _}=e, acc ->
	Map.put(acc, id, e)
      end)
    # WARNING! the tricky point is here, take only child specs with an id
    # which is associate with the current node in the ring
    remote_children_keys = all_children |>
      Map.keys() |>
      Enum.filter(&ConsistentHash.get_node(ring, {sup_ref, &1}) !== node())
    wanted_children = all_children |> Map.drop(remote_children_keys)
    
    ## kill all the local children which should not be in the node, get/start
    ## child on the correct node to migrate state if needed
    :ok = cur_children |>
      Enum.filter(fn {id, _} ->
	not Map.has_key?(wanted_children, id)
      end) |>
      Enum.each(fn {id, {id, child, type, modules}} ->
	new_node = ConsistentHash.get_node(ring, {sup_ref, id})
	if is_pid(child) do
	  call_args = [Supervisorring.local_sup_ref(sup_ref), Map.get(all_children, id)]
          case :rpc.call(new_node, Supervisor, :start_child, call_args) do
            {:error, {:already_started, existingpid}} ->
	      callback.migrate({id, type, modules}, child, existingpid)
            {:ok, newpid} ->
	      callback.migrate({id, type, modules}, child, newpid)
            _ ->
	      :ok
          end
          sup_ref |> Supervisorring.local_sup_ref() |> Supervisor.terminate_child(id)
	end
	sup_ref |> Supervisorring.local_sup_ref() |> Supervisor.delete_child(id)
      end)
    :ok = wanted_children |>
      Enum.filter(fn {id, _} ->
	not Map.has_key?(cur_children, id)
      end) |>
      Enum.each(fn {_, childspec} -> 
	Supervisor.start_child(Supervisorring.local_sup_ref(sup_ref), childspec)
      end)
    {:noreply, %{state | ring: ring}}
  end

  ###
  ### Priv
  ###
  defp expand_specs(specs) do
    {spec_generators, child_specs} = specs |>
      Enum.split_with(&match?({:dyn_child_handler, _}, &1))
    Enum.concat(child_specs, spec_generators |>
      Enum.flat_map(fn {:dyn_child_handler, handler} ->
	handler.get_all
      end))
  end
end
