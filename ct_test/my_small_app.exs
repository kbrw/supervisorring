#one app with 2 clients on one ring
defmodule MySmallApp do
  use Application

  defmodule SupRing do
    use Supervisorring
    
    def migrate(a, b, c), do: MyApp.SupRing.migrate(a, b, c)
    def init(ring_name),
      do: MyApp.SupRing.init(__MODULE__, ring_name, __MODULE__)
    @behaviour :dyn_child_handler
    def match(_), do: true
    def get_all, do: "childs" |> File.read! |> :erlang.binary_to_term
    def add(childspec), do: MyApp.SupRing.add(childspec, "childs")
    def del(childspec), do: MyApp.SupRing.del(childspec, "childs")
    def start_link(sup_name) do
      {ok, args} = MySmallApp.SupRing.init(:test_ring)
      :supervisorring.start_link(sup_name, __MODULE__, args)
    end
  end

  defmodule Sup do
    use Supervisor

    def init(_) do
      name = MySmallApp.SupRing
      child = worker(name, [{:local, name}], id: name)
      supervise([child], strategy: :one_for_one)
    end
  end

  def start(_type, args), do: Supervisor.start_link(MySmallApp.Sup, args)
end

