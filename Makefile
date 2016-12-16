.SECONDARY:

all: deps supervisorring

deps: 
	@mix do deps.get

supervisorring:
	@mix compile

## single node dev
start: supervisorring
	@iex -S mix run

start_%: config/%.exs data/%
	@iex --name $*@127.0.0.1 -S mix run
test_%: config/%.exs data/%
	rm -f data/$*/ring
	@iex --name $*@127.0.0.1 -S mix run -e "Code.require_file(\"test/multinode.exs\");ExUnit.run"

## multiple node dev
NODES = dev1 dev2 dev3 dev4
multi_start: supervisorring
	@for n in $(NODES); do xterm -e "make start_$$n ; read" & done
multi_test: supervisorring
	@for n in $(NODES); do xterm -e "make test_$$n ; read" & done

data/%:
	mkdir -p "$@"
