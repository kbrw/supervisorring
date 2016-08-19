#! /bin/sh

if [ ! $# -eq 1 ] ; then
	echo "You must provide the name of a common_test spec file"
	exit 1
fi

mix compile
logdir=./ct_logs

cd ct_test
erlc ct_elixir_wrapper.erl
cd ..

[ ! -d $logdir ] && mkdir -p $logdir

HOST=`hostname`

# generate a spec file for two clusters of 4 nodes with all nodes on
# local host
if [ ! -e $1 ] ; then
	for NODE in n1 n2 n3 n4 n5 n6 n7 n8
		do echo "{node, $NODE, $NODE@$HOST}." >> $1
	done
	cat dist.spec_template >> $1
fi

elixir --erl "-s init stop" \
    --sname ct_master@$HOST \
    -e "\
        Mix.start ; \
        Code.load_file(\"mix.exs\") ; \
        Mix.Project.get! ; \
        Mix.Task.run(\"loadpaths\"); \
        :ct_master.run('$1')"
