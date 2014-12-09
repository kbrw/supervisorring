defmodule Supervisorring.Mixfile do
  use Mix.Project

  def project do
    [ app: :supervisorring,
      version: "0.0.3",
      elixir: "~> 1.0.0",
      deps: [{:nano_ring,"0.0.2",git: "git://github.com/awetzel/nano_ring"}]]
  end

  def application do
    [ mod: { Supervisorring.App,[] },
      applications: [:nano_ring,:iex],
      env: [ data_dir: "./data" ] ]
  end
end
