use Mix.Config
sname = "#{node}" |> String.split("@") |> hd

if sname != "nonode" do
  import_config "#{sname}.exs"
else
  config :gen_serverring, data_dir: "data"
end
