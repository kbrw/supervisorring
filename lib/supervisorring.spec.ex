defmodule Supervisorring.Spec do
  @moduledoc """
  Handle specs for Supervisoring children
  """

  defdelegate worker(module, args), to: Supervisor.Spec
  defdelegate worker(module, args, options), to: Supervisor.Spec

  defdelegate supervisor(module, args), to: Supervisor.Spec
  defdelegate supervisor(module, args, options), to: Supervisor.Spec

  @doc """
  Defines a child_handler children
  """
  @spec child_handler(module) :: {:dyn_child_handler, module}
  def child_handler(module) when is_atom(module), do: {:dyn_child_handler, module}
end
