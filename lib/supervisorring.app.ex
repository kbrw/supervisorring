defmodule Supervisorring.App do
  @moduledoc """
  Supervisorring OTP application entry point
  """
  use Application

  alias Supervisorring.Spec

  @doc """
  Start the application
  """
  @spec start(Application.start_type, term) :: {:ok, pid} | {:error, term}
  def start(_type,_args) do
    Supervisor.start_link([
      Spec.worker(:gen_event, [{:local, Supervisorring.Events}]),
      Spec.worker(Supervisorring.Nodes, []),
      Spec.worker(Supervisorring.SuperSup, [])
    ], strategy: :one_for_all)
  end
end
