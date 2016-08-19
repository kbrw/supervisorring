-module(crash_node_SUITE).

-export([all/0, init_per_suite/1]).

-export([crash_node_test/1]).

all() -> [crash_node_test].

init_per_suite(Config) ->
    ct_elixir_wrapper:elixir_file("test_util.exs"),
    ct_elixir_wrapper:elixir_file("ring_util.exs"),
    ct_elixir_wrapper:elixir_file("my_small_app.exs"),
    ct_elixir_wrapper:elixir_file("verbose_ring.exs"),
		Config.

crash_node_test(_) ->
    ct_elixir_wrapper:run_elixir_test('crash_node_test.exs').
	
