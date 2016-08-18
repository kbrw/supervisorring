%%% @author Laurent Picouleau <laurent@kbrwadventure.com>
%%% @doc
%%% inspired from
%%% <https://github.com/processone/ejabberd/blob/master/test/elixir_SUITE.erl>
%%% @end

-module(ct_elixir_wrapper).

-export([init/0, run_elixir_test/1, test_dir/0]).

init() ->
    clone_path(hd(nodes())),
    application:start(compiler),
    application:start(elixir),
    'Elixir.Application':start(iex),
    'Elixir.Application':start(logger).


run_elixir_test(Func) ->
    %% Elixir tests can be tagged as follow to be ignored (place before test
    %% start)
    %% @tag pending: true

    'Elixir.ExUnit':start([{exclude, [{pending, true}]},
        {formatters, ['Elixir.ExUnit.CLIFormatter']}]),

    'Elixir.Code':load_file(list_to_binary(filename:join(test_dir(),
        atom_to_list(Func)))),
    ResultMap = 'Elixir.ExUnit':run(),

    case maps:find(failures, ResultMap) of
        {ok, 0} -> ok;
        {ok, Failures} ->
            ct:print("Tests failed in module '~s': ~.10B failures.~nSee logs",
                [Func, Failures]),
            ct:fail(elixir_test_failure),
            error
    end.


test_dir() ->
    {ok, CWD} = file:get_cwd(),
    filename:join(CWD, "../../ct_test").


clone_path(Node) ->
    Path = rpc:call(Node,  code, get_path, []),
    true = code:set_path(Path).
