defmodule Mix.DistEnv do
  @moduledoc """
  Start / stops slave nodes for distributed testing

  Inspired by: https://github.com/am-kantox/distributed_test/
  """
  use GenServer

  require Logger

  defmodule State do
    defstruct master: nil, slaves: MapSet.new(), name: nil
  end

  @timeout 30_000
  @host "127.0.0.1"

  @doc false
  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def start_slaves(snames), do: GenServer.call(__MODULE__, {:start, snames}, 5_000 * Enum.count(snames))

  @doc false
  def stop_slaves, do: GenServer.call(__MODULE__, :stop)

  @doc false
  def stop_slave(sname), do: GenServer.call(__MODULE__, {:stop, :"#{sname}"})

  @doc false
  def nodes, do: GenServer.call(__MODULE__, :nodes)

  @doc false
  def slaves, do: GenServer.call(__MODULE__, :slaves)

  @doc false
  def stop do
    case GenServer.whereis(__MODULE__) do
      nil -> :error
      _ref -> GenServer.stop(__MODULE__)
    end
  end

  ###
  ### GenServer callbacks
  ###
  def init(_) do
    :net_kernel.start([:"test@#{@host}"])
    :erl_boot_server.start([])
    allow_boot(~c"#{@host}")
    {:ok, %State{ master: node() }}
  end

  def handle_call({:start, snames}, _, s), do: spawn_slaves(snames, s)
  def handle_call(:stop,            _, s), do: halt_slaves(s.slaves |> Enum.to_list(), s)
  def handle_call({:stop, sname},   _, s), do: halt_slaves([sname], s)
  def handle_call(:slaves,          _, s), do: {:reply, s.slaves, s}
  def handle_call(:nodes,           _, s), do: {:reply, MapSet.put(s.slaves, s.master), s}

  def handle_info({:nodedown, node}, s) do
    Logger.info("SLAVE down: #{node}")
    {:noreply, %{ s | slaves: MapSet.delete(s.slaves, node)}}
  end
  def handle_info(_, s), do: {:noreply, s}
  
  def terminate(_, s) do
    _ = halt_slaves(s.slaves |> Enum.to_list(), s)
    :ok
  end

  ###
  ### Priv
  ###
  defp spawn_slaves(snames, s) do
    snames |>
      Stream.map(&Task.async(fn -> spawn_slave(&1) end)) |>
      Stream.map(&Task.await(&1, @timeout)) |>
      Enum.reduce_while({:reply, :ok, s}, fn
	{:ok, slave}, {_, _, acc} ->
	  {:cont, {:reply, :ok, %{ acc | slaves: MapSet.put(acc.slaves, slave) }}}
	{:error, e}, {_, _, acc} -> {:halt, {:reply, {:error, e}, acc}}
      end)
  end

  def spawn_slave(sname) do
    Logger.info("START #{sname}")

    # Can not use start_link as we launch through Task
    case :slave.start(~c"#{@host}", :"#{sname}", inet_loader_args()) do
      {:ok, node} ->
	true = Node.monitor(node, true)
	add_code_paths(node)
	transfer_configuration(node)
	ensure_applications_started(node)
	{:ok, node}
      {:error, _}=e -> e
    end
  end

  defp halt_slaves([], s), do: {:reply, :ok, s}
  defp halt_slaves([ sname | rest ], %State{ slaves: slaves }=s) do
    node = to_fullname(sname)
    if node in slaves do
      Logger.info("STOP #{node}")
      :rpc.call(node, :erlang, :halt, [0])
      halt_slaves(rest, %{ s | slaves: MapSet.delete(slaves, node) })
    else
      {:reply, {:error, {:invalid_slave, node}}, s}
    end
  end

  defp allow_boot(host) do
    with {:ok, ipv4} <- :inet.parse_ipv4_address(host),
      do: :erl_boot_server.add_slave(ipv4)
  end

  defp inet_loader_args do
    ~c"-loader inet -hosts #{@host} -setcookie #{:erlang.get_cookie()}"
  end

  defp add_code_paths(node) do
    :rpc.block_call(node, :code, :add_paths, [:code.get_path()])
  end

  defp transfer_configuration(node) do
    for {app_name, _, _} <- Application.loaded_applications() do
      for {key, val} <- Application.get_all_env(app_name) do
	:rpc.block_call(node, Application, :put_env, [app_name, key, val])
      end
    end
  end

  defp ensure_applications_started(node) do
    :rpc.block_call(node, Application, :ensure_all_started, [:mix])
    :rpc.block_call(node, Mix, :env, [Mix.env()])
    loaded_apps = Application.loaded_applications() |> Enum.map(&(elem(&1, 0)))
    for app_name <- loaded_apps do
      :rpc.block_call(node, Application, :ensure_all_started, [app_name])
    end
  end

  defp to_fullname(name) do
    case String.split("#{name}", "@") do
      [_sname, _hostname] -> :"#{name}"
      [_sname] -> :"#{name}@#{@host}"
    end
  end
end
