defmodule Supervisorring.Mixfile do
  use Mix.Project

  def project do
    [ app: :supervisorring,
      version: "0.0.3",
      elixir: "~> 1.3",
      deps: [{:nano_ring, git: "git://github.com/awetzel/nano_ring"}]]
  end

  def application do
    [ mod: { Supervisorring.App,[] },
      applications: [:nano_ring,:iex],
      env: [ data_dir: "./data" ] ]
  end
end
