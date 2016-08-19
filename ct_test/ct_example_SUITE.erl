% A short example suite showing how to use the ct_elixir wrapper
-module(ct_example_SUITE).

-export([all/0, init_per_suite/1]).

-export([example_test/1]).

% standard, simply give the list of tests that the suite should run
all() -> [example_test].

% classical also, just that if you want to use some .exs file(s) you have to 
% Code.load_file/1 them. If different suites need different codes to be loaded
% it is a good place to deal with it.
init_per_suite(Config) ->
    ct_elixir_wrapper:elixir_file("test_util.exs"),
    ct_elixir_wrapper:elixir_file("buggy_client.exs"),
    ct_elixir_wrapper:elixir_file("standard_ring.exs"),
    Config.

% you can use classical (erlang test) or launch an ExUnit test file. In the
% later case, simply run the file with ct_elixir_wrapper:run_elixir_test/1
example_test(_) -> ct_elixir_wrapper:run_elixir_test('ct_example_test.exs').
