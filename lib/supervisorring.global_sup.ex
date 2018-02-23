defmodule Supervisorring.GlobalSup do
  @moduledoc """
  Cluster-wide supervisor: supervises node status.

  Notifies local supervisors which children they need to supervise.
  """
  use Supervisor

  alias Supervisor.Spec

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
    
    localsup_spec = Spec.supervisor(Supervisorring.LocalSup, [sup_ref, strategy])
    childman_spec = Spec.worker(Supervisorring.ChildManager, [sup_ref, specs, module])
    
    # Nodes Workers are bounded to directory manager
    {:ok, {%{strategy: :one_for_all}, [localsup_spec, childman_spec]}}
  end
end
