defmodule Supervisorring.SuperSup do
  @moduledoc """
  Propagate global supervisors death to all nodes
  """
  use GenServer

  @doc """
  Start super sup
  """
  @spec start_link() :: {:ok, pid} | {:error, term}
  def start_link, do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Start monitoring an item. Called by GlobalSup at startup

  See `Process.monitor`
  """
  @spec monitor(atom | pid) :: :ok
  def monitor(item), do: GenServer.cast(__MODULE__, {:monitor, item})

  ###
  ### GenServer callbacks
  ###
  @doc false
  def init(nil), do: {:ok, nil}

  @doc false
  def handle_cast({:monitor, item}, nil) do
    _ref = Process.monitor(item)
    {:noreply, nil}
  end
  def handle_cast({:terminate, global_sup_ref}, nil) do
    true = Process.exit(Process.whereis(global_sup_ref), :kill)
    {:noreply, nil}
  end

  @doc false
  def handle_info({:DOWN, _ref, :process, _, :killed}, nil), do: {:noreply, nil}
  def handle_info({:DOWN, _ref, :process, {global_sup_ref, _}, _}, nil) do
    # Propagate death to other nodes
    Supervisorring.Nodes.up() |> Enum.filter(&(&1 != node())) |> Enum.each(fn n ->
      GenServer.cast({__MODULE__, n}, {:terminate, global_sup_ref})
    end)
    {:noreply, nil}
  end
end
