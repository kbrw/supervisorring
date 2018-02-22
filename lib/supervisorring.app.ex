defmodule Supervisorring.App do
  @moduledoc """
  Supervisorring OTP application entry point
  """
  use Application

  @doc """
  Start the application
  """
  @spec start(Application.start_type, term) :: {:ok, pid} | {:error, term}
  def start(_type,_args) do
    events_spec = %{
      id: Supervisorring.Events,
      start: {:gen_event, :start_link, [{:local, Supervisorring.Events}]},
      type: :worker
    }
    super_spec = %{
      id: Supervisorring.SuperSup,
      start: {Supervisorring.SuperSup, :start_link, []}
    }
    Supervisor.start_link([events_spec, super_spec], strategy: :one_for_one)
  end
end
