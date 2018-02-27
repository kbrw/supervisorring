use Mix.Config

if Mix.env == :test do
  config :logger, :console,
    format: "<$node> $time [$level] $message\n"
  # config :kernel, :dist_auto_connect, false
end
