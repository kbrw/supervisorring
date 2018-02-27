defmodule Mix.Tasks.Test.Distributed do
  @moduledoc """
  Run tests for a distributed application.
  This mix task starts up a cluster of nodes before running the `Mix.Tasks.Test`
  mix task. The number of nodes to start (besides the master node) can be set
  using the "-count #" switch (defaults to 4). Each slave node will have the code
  and application environment from the master node loaded onto it.  All switches
  for the `mix test` task will be passed along to it.

  Credits: from https://github.com/sschneider1207/distributed_test
  """
  use Mix.Task

  @shortdoc "Runs a project's tests in a distributed environment"
  @recursive true
  @preferred_cli_env :test

  def run(params) do
    Mix.env(:test)

    app = Mix.Project.config[:app]
    Application.ensure_started(app)

    {:ok, _} = Mix.DistEnv.start_link()

    Mix.Tasks.Test.run(params)
    
    Mix.DistEnv.stop()
  end
end
