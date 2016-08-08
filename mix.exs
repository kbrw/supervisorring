defmodule Supervisorring.Mixfile do
  use Mix.Project

  def project do
    [ app: :supervisorring,
      version: "0.0.4",
      elixir: "~> 1.2",
      deps: [
        {:gen_serverring, "0.0.2",
          git: "https://github.com/shopping-adventure/gen_serverring.git"}]]
  end

  def application do
    [ mod: {Supervisorring.App, []},
      applications: [:gen_serverring, :iex],
      env: [data_dir: "./data", gen_serverring_name: [:test_ring]]]
  end
end
