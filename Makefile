.SECONDARY:

all: deps supervisorring

deps: 
	@mix do deps.get

supervisorring:
	@mix compile

## single node dev
start: supervisorring sys.config
	@iex --erl "-config sys -name supervisorring@127.0.0.1" -S mix run

start_%: %.config %_data
	@iex --erl "-config $* -name supervisorring_$*@127.0.0.1" -S mix run
test_%: %.config %_data
	@iex --erl "-config $* -name supervisorring_$*@127.0.0.1" -S mix run -e "Code.require_file(\"test/multinode.exs\");ExUnit.run"

## multiple node dev
NODES = dev1 dev2 dev3 dev4
multi_start: supervisorring
	@for n in $(NODES); do xterm -e "make start_$$n ; read" & done
multi_test: supervisorring
	@for n in $(NODES); do xterm -e "make test_$$n ; read" & done

## Erlang configuration management using Mix
## (name).config is defined by the merge of mix confs : sys_config and (name)_config
%.config: mix.exs
	MIX_ENV=$* mix run -e 'File.write!("$@", :io_lib.format("~p.~n",[\
        (Mix.project[:default_config]||[]) |> ListDict.merge(Mix.project[:config]||[],fn(_,conf1,conf2)->ListDict.merge(conf1,conf2) end)\
    ]))'

%_data:
	mkdir "$@"
