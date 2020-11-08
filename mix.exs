defmodule Supervisorring.Mixfile do
  use Mix.Project

  def project do
    [ app: :supervisorring,
      version: "1.0.0",
      elixir: "~> 1.10",
      deps: [{:nano_ring,"~> 1.0.0",git: "https://github.com/kbrw/nano_ring", branch: "master-1.10"}]]
  end

  def application do
    [ mod: { Supervisorring.App,[] },
      applications: [:nano_ring,:iex,:crypto],
      env: [ data_dir: "./data" ] ]
  end
end
