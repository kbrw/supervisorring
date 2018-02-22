defmodule Supervisorring.LocalSup do
  @moduledoc """
  Each global supervisor starts a local supervisor, with no
  children. Children are added dynamically when global supervisor
  decides so.
  """
  use Supervisor

  @doc """
  Start a local supervisor
  """
  @spec start_link(atom, Supervisor.strategy) :: Supervisor.on_start
  def start_link(sup_ref, strategy) do
    Supervisor.start_link(__MODULE__, strategy, name: Supervisorring.local_sup_ref(sup_ref))
  end

  ###
  ### Supervisor callback
  ###
  def init(strategy), do: {:ok, {strategy, []}}
end
