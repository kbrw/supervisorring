defmodule Supervisorring.Mixfile do
  use Mix.Project

  def project do
    [
      app: :supervisorring,
      version: "0.2.0",
      elixir: "~> 1.3",
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application, do: [
    mod: { Supervisorring.App,[] },
    extra_applications: [:logger],
    env: [
      data_dir: {:priv_dir, "data"},
      refresh_nodes: 5_000
    ]
  ]

  defp deps, do: [
    {:ex_doc, ">= 0.0.0", only: :dev}
  ]

  defp package, do: [
    maintainers: [
      "Arnaud Wetzel <arnaud.wetzel@kbrw.fr>",
      "Jean Parpaillon <jparpaillon@kbrw.fr>"
    ],
    licenses: ["Apache License 2.0"],
    links: %{ "GitHub" => "https://github.com/kbrw/supervisorring" },
    source_url: "https://github.com/kbrw/supervisorring"
  ]

  defp docs, do: [
    main: "readme",
    extras: [ "README.md" ],
    source_url: "https://gtihub.com/kbrw/supervisorring"
  ]
end
