defmodule Supervisorring.Mixfile do
  use Mix.Project

  def project do
    [ app: :supervisorring,
      version: "0.0.1",
      elixir: "~> 0.12.0",
      deps: [{:nano_ring,"0.0.1",git: "git://github.com/awetzel/nano_ring"}],
      ## dev multi nodes configs
      env: [
        dev1: [ config: [nano_ring: [data_dir: "./dev1_data"]] ],
        dev2: [ config: [nano_ring: [data_dir: "./dev2_data"]] ],
        dev3: [ config: [nano_ring: [data_dir: "./dev3_data"]] ],
        dev4: [ config: [nano_ring: [data_dir: "./dev4_data"]] ]
      ]
    ]
  end

  def application do
    [ mod: { Supervisorring.App,[] },
      applications: [:nano_ring,:iex],
      env: [ data_dir: "./data" ] ]
  end
end
