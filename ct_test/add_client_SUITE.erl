-module(add_client_SUITE).

-export([all/0, init_per_suite/1]).

-export([add_client_test/1]).

all() -> [add_client_test].

init_per_suite(Config) ->
    ct_elixir_wrapper:elixir_file("test_util.exs"),
    ct_elixir_wrapper:elixir_file("ring_util.exs"),
    ct_elixir_wrapper:elixir_file("my_small_app.exs"),
		Config.

add_client_test(_) ->
    ct_elixir_wrapper:run_elixir_test('add_client_test.exs').
	
