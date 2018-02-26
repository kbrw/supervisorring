defmodule Supervisorring.Nodes do
  @moduledoc """
  Handle nodes status
  """
  use GenServer

  require Logger

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
  Reset cluster state

  Remove state file(s) and disconnect nodes
  """
  @spec reset() :: :ok
  def reset, do: GenServer.cast(__MODULE__, :reset)

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
  def join(node), do: GenServer.cast(__MODULE__, {:join, :"#{node}"})

  @doc """
  Leave the cluster
  """
  @spec leave(node) :: :ok
  def leave(node), do: GenServer.cast(__MODULE__, {:leave, :"#{node}"})

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
  def handle_call(:up, _, s), do: {:reply, s.up, s}
  def handle_call(:nodes, _, s), do: {:reply, s.nodes, s}

  @doc false
  def handle_cast({:join, node}, %State{ nodes: nodes }=s) do
    Logger.debug("CONNECT #{node}")
    _ = Node.connect(node)
    {:noreply, write_state(%{ s | nodes: MapSet.put(nodes, node)})}
  end
  def handle_cast({:leave, node}, %State{ nodes: nodes }=s) do
    Logger.debug("DISCONNECT #{node}")
    _ = Node.disconnect(node)
    s = %{ s | nodes: MapSet.delete(nodes, node) }
    :ok = :gen_event.notify(Supervisorring.Events, :node_change)    
    {:noreply, write_state(s)}
  end
  def handle_cast(:refresh, %State{ nodes: nodes, up: up }=s) do
    :ok = Enum.each(MapSet.difference(nodes, up), &(Node.connect(&1)))
    {:noreply, s}
  end
  def handle_cast(:reset, %State{ nodes: nodes }) do
    :ok = Enum.each(nodes, &(Node.disconnect(&1)))
    _ = File.rm(data_path())
    {:noreply, read_state()}
  end

  @doc false
  def handle_info({node_info, n}, %State{}=s) do
    s = case node_info do
	  :nodeup ->
	    Logger.info("UP #{n}")
	    %{ s | nodes: MapSet.put(s.nodes, n), up: MapSet.put(s.up, n) }
	  :nodedown ->
	    Logger.info("DOWN #{n}")
	    %{ s | up: MapSet.delete(s.up, n)}
	end
    :ok = :gen_event.notify(Supervisorring.Events, :node_change)
    {:noreply, write_state(s)}
  end

  @doc false
  def terminate(_, _s), do: :ok

  ###
  ### Priv
  ###
  defp data_path do
    case Application.get_env(:supervisorring, :data_dir, System.tmp_dir!()) do
      {:priv_dir, path} -> Path.join [:code.priv_dir(:supervisorring), path, "nodes"]
      path when is_binary(path) -> Path.join [path, "nodes"]
    end
  end

  defp read_state do
    case File.read(data_path()) do
      {:ok, bin} ->
	%State{ nodes: :erlang.binary_to_term(bin), up: MapSet.new() }
      _ ->
	nodes = [node()]
	up = if Node.alive?(), do: [node()], else: []
	%State{ nodes: MapSet.new(nodes), up: MapSet.new(up) }
    end
  end

  defp write_state(%State{ nodes: nodes }=s) do
    path = data_path()
    _ = File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(nodes))
    s
  end
end
