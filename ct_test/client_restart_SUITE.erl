-module(client_restart_SUITE).

-export([all/0, init_per_suite/1]).

-export([client_restart_test/1]).

all() -> [client_restart_test].

init_per_suite(Config) ->
    ct_elixir_wrapper:elixir_file("test_util.exs"),
    ct_elixir_wrapper:elixir_file("buggy_client.exs"),
    Config.

client_restart_test(_) ->
    ct_elixir_wrapper:run_elixir_test('buggy_client_test.exs').
