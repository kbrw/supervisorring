defmodule Supervisorring.SuperSup do
  @moduledoc """
  Supervise cluster events listener
  """
  use GenServer

  @doc """
  Start super sup
  """
  @spec start_link() :: {:ok, pid} | {:error, term}
  def start_link, do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  ###
  ### GenServer callbacks
  ###
  @doc false
  def init(nil) do
    :gen_event.add_sup_handler(NanoRing.Events, NodesListener,
      ConsistentHash.new(NanoRing.up()))
    {:ok, nil}
  end

  @doc false
  def handle_cast({:monitor, global_sup_ref}, nil) do
    Process.monitor(global_sup_ref)
    {:noreply, nil}
  end
  def handle_cast({:terminate, global_sup_ref}, nil) do
    true = Process.exit(Process.whereis(global_sup_ref), :kill)
    {:noreply, nil}
  end

  @doc false
  def handle_info({:DOWN,_, :process, _, :killed}, nil), do: {:noreply, nil}
  def handle_info({:DOWN,_, :process, {global_sup_ref, _}, _}, nil) do
    NanoRing.up() |> Enum.filter(&(&1 != node())) |> Enum.each(fn n ->
      GenServer.cast({__MODULE__, n}, {:terminate, global_sup_ref})
    end)
    {:noreply, nil}
  end
  def handle_info({:gen_event_EXIT, _, _}, nil), do: exit(:ring_listener_died)
end
