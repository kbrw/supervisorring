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
	@iex --erl "-config $* -name supervisorring$*@127.0.0.1" -S mix run

## multiple node dev
NODES = dev1 dev2 dev3 dev4
multi_start: supervisorring
	@for n in $(NODES); do xterm -e "make start_$$n ; read" & done

## Erlang configuration management using Mix
## (name).config is defined by the merge of mix confs : sys_config and (name)_config
%.config: mix.exs
	mix run -e 'File.write!("$@", :io_lib.format("~p.~n",[\
        (Mix.project[:sys_config]||[]) |> ListDict.merge(Mix.project[:$*_config]||[],fn(_,conf1,conf2)->ListDict.merge(conf1,conf2) end)\
    ]))'

%_data:
	mkdir "$@"
