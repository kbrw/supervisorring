defmodule Supervisorring.Nodes do
  @moduledoc """
  Handle nodes status
  """
  use GenServer

  defmodule State do
    @moduledoc false
    defstruct nodes: MapSet.new(), up: MapSet.new()
  end

  @typedoc "Nodes changes messages"
  @type node_change :: :node_change

  @doc """
  Start nodes listener
  """
  @spec start_link :: GenServer.on_start
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns list of up nodes
  """
  @spec up() :: [node]
  def up, do: GenServer.call(__MODULE__, :up)

  @doc """
  Returns list of all nodes
  """
  @spec nodes() :: [node]
  def nodes, do: GenServer.call(__MODULE__, :nodes)

  @doc """
  Join the cluster
  """
  @spec join(node) :: :ok
  def join(node), do: GenServer.cast(__MODULE__, {:join, node})

  @doc """
  Leave the cluster
  """
  @spec leave(node) :: :ok
  def leave(node), do: GenServer.cast(__MODULE__, {:leave, node})

  @doc """
  Subscribe to nodes changes
  """
  @spec subscribe(handler :: module, args :: any) :: :ok
  def subscribe(handler, args) do
    :gen_event.add_sup_handler(Supervisorring.Events, handler, args)
  end

  ###
  ### GenServer callbacks
  ###
  @doc false
  def init(_) do
    :ok = :net_kernel.monitor_nodes(true)
    %State{ nodes: nodes }=s0 = read_state()
    :ok = Enum.each(nodes, &(:net_kernel.connect_node(&1)))

    # Try to connect down nodes every `:refresh_nodes` ms
    :timer.apply_interval(Application.get_env(:supervisorring, :refresh_nodes, 5_000),
      GenServer, :cast, [__MODULE__, :refresh])
    
    {:ok, s0}
  end

  @doc false
  def handle_call(:up, s), do: {:ok, s.up, s}
  def handle_call(:nodes, s), do: {:ok, s.nodes, s}

  @doc false
  def handle_cast({:join, node}, %State{ nodes: nodes }=s) do
    _ = :net_kernel.connect_node(node)
    {:noreply, write_state(%{ s | nodes: MapSet.put(nodes, node)})}
  end
  def handle_cast({:leave, node}, %State{ nodes: nodes, up: up }=s) do
    s = %{ s | nodes: MapSet.delete(nodes, node), up: MapSet.delete(up, node) }
    :ok = :gen_event.notify(Supervisorring.Events, :node_change)    
    {:noreply, write_state(s)}
  end
  def handle_cast(:refresh, %State{ nodes: nodes, up: up }=s) do
    :ok = Enum.each(MapSet.difference(nodes, up), &(:net_kernel.connect_node(&1)))
    {:noreply, s}
  end

  @doc false
  def handle_info({node_info, n}, %State{}=s) do
    s = case node_info do
	  :nodeup ->
	    %{ s | nodes: MapSet.put(s.nodes, n), up: MapSet.put(s.up, n) }
	  :nodedown ->
	    %{ s | up: MapSet.delete(s.up, n)}
	end
    :ok = :gen_event.notify(Supervisorring.Events, :node_change)
    {:ok, write_state(s)}
  end

  @doc false
  def terminate(_, _s), do: :ok

  ###
  ### Priv
  ###
  defp data_path do
    Path.join Application.get_env(:sueprvisorring, :data_dir, "./data"), "nodes"
  end

  defp read_state do
    case File.read(data_path()) do
      {:ok, bin} ->
	%State{ nodes: :erlang.binary_to_term(bin), up: MapSet.new() }
      _ ->
	%State{ nodes: MapSet.new(), up: MapSet.new() }
    end
  end

  defp write_state(%State{ nodes: nodes }=s) do
    File.write!(data_path(), :erlang.term_to_binary(nodes))
    s
  end
end
