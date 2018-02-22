defmodule Supervisorring.GlobalSup do
  @moduledoc """
  Cluster-wide supervisor: supervises node status.

  Notifies local supervisors which children they need to supervise.
  """
  use Supervisor

  @doc """
  Start a global supervisor
  """
  @spec start_link(atom, {module, term}) :: Supervisor.on_start
  def start_link(sup_ref, {module, args}) when is_atom(sup_ref) do
    Supervisor.start_link(__MODULE__, {sup_ref, {module, args}},
      name: Supervisorring.global_sup_ref(sup_ref))
  end

  ###
  ### Supervisor callbacks
  ###
  def init({sup_ref, {module, args}}) do
    {:ok, {strategy, specs}} = module.init(args)

    GenServer.cast(Supervisorring.SuperSup, {:monitor, Supervisorring.global_sup_ref(sup_ref)})
    
    localsup_spec = %{ id: Supervisorring.LocalSup,
		       start: {Supervisorring.LocalSup, [sup_ref, strategy]},
		       type: :supervisor }
    childman_spec = %{ id: Supervisorring.ChildManager,
		       start: {Supervisorring.ChildManager, [sup_ref, specs, module]},
		       type: :worker }

    # Nodes Workers are bounded to directory manager
    supervise([localsup_spec, childman_spec], strategy: :one_for_all) 
  end
end
