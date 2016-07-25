use Mix.Config
sname = "#{node}" |> String.split("@") |> hd

if sname != "nonode" do
  import_config "#{sname}.exs"
else
  [gen_serverring: [data_dir: "data"]]
end
