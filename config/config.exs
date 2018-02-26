use Mix.Config
sname = "#{node()}" |> String.split("@") |> hd()

if sname != "nonode" do
  import_config "#{sname}.exs"
else
  config :supervisorring, data_dir: {:priv_dir, "data"}
end
