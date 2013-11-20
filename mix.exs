defmodule Supervisorring.Mixfile do
  use Mix.Project

  def project do
    [ app: :supervisorring,
      version: "0.0.1",
      elixir: "~> 0.11.0",
      deps: [{:nano_ring,"0.0.1",git: "git://github.com/awetzel/nano_ring"}],
      ## dev multi nodes configs
      dev1_config: [nano_ring: [data_dir: "./dev1_data"]],
      dev2_config: [nano_ring: [data_dir: "./dev2_data"]],
      dev3_config: [nano_ring: [data_dir: "./dev3_data"]],
      dev4_config: [nano_ring: [data_dir: "./dev4_data"]] 
    ]
  end

  def application do
    [ mod: { Supervisorring.App,[] },
      applications: [:nano_ring,:iex],
      env: [ data_dir: "./data" ] ]
  end
end
