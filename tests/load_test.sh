#!/bin/bash

GOPATH=`pwd`/.go

PROCESS=./qp
CONCURRENT=10
MAX_DSNS=8
PORT=9666
URL=:$PORT

function cleanup {
    kill $PID
    kill $SSH_TUNNEL_PID
}
trap cleanup EXIT

function die {
    echo $1
    exit 666
}

# If called with no arguments a new timer is returned.
# If called with arguments the first is used as a timer
# value and the elapsed time is returned in the form HH:MM:SS.
#
function timer()
{
    if [[ $# -eq 0 ]]; then
        echo $(date '+%s')
    else
        local  stime=$1
        etime=$(date '+%s')

        if [[ -z "$stime" ]]; then stime=$etime; fi

        dt=$((etime - stime))
        ds=$((dt % 60))
        dm=$(((dt / 60) % 60))
        dh=$((dt / 3600))
        printf '%d:%02d:%02d' $dh $dm $ds
    fi
}

QUERY="$(cat tests/load_test_query.sql)"

TUNNEL_HOST=$1
if [[ ! $TUNNEL_HOST ]]; then
    die "Please supply username@hostname for MySQL tunnels"
fi
TUNNELS=""
QS=()
START_PORT=20889
for i in $(seq 1 $MAX_DSNS); do
    port=$((START_PORT + i))
    Q="{\"dsn\":\"root@tcp(127.0.0.1:$port)/monetate_session?charset=utf8\",\"query\":\"__QUERY__\"}"
    QS=(${QS[@]} $Q)    
    Q="{\"dsn\":\"root@tcp(127.0.0.1:$port)/monetate_session?charset=utf8\",\"query\":\"__QUERY__\"}"
    QS=(${QS[@]} $Q)
    TUNNELS="$TUNNELS -L$port:127.0.0.1:3306"
done

echo "Opening ssh tunnels to mysql..."
ssh -N $TUNNELS $TUNNEL_HOST &
SSH_TUNNEL_PID=$!
echo "Started ssh tunnel to $TUNNEL_HOST with pid:$SSH_TUNNEL_PID"

ALL_Q=${QS[@]}
SHARDS=$(echo "${ALL_Q// /|}" | sed -e "s/__QUERY__/$QUERY/g")

QUIET=$2
if [ QUIET ]; then
    $PROCESS -url $URL -maxDsns=$MAX_DSNS -maxConnsPerDsn=24 2>&1 1>/dev/null &
else
    $PROCESS -url $URL -maxDsns=$MAX_DSNS -maxConnsPerDsn=24 2>&1 1>/dev/null &
fi
PID=$!
echo "Started qp process pid:$PID"
sleep 1

ITERATIONS=5

tmr=$(timer)
SHARDQ=$(echo $SHARDS | tr "|" ",")
for i in $(seq 1 $ITERATIONS); do
    for j in $(seq 1 $CONCURRENT); do
        Q="{\"flat\":true,\"queries\":[$SHARDQ]}"
        python -c "import requests; requests.post('http://localhost:$PORT/', '$Q')" &
        PIDS[${j}]=$!
    done
    echo "iteration process ids: ${PIDS[*]}"
    for p in ${PIDS[*]}; do
        wait $p
    done
    unset PIDS
done
T1=$(timer $tmr)

tmr=$(timer)
for i in $(seq 1 $ITERATIONS); do
    OLDIFS=$IFS
    IFS=$'|'
    for j in $SHARDS; do
        for k in $(seq -s "|" 1 $CONCURRENT); do
            Q="{\"flat\":true,\"queries\":[$j]}"
            python -c "import requests; requests.post('http://localhost:$PORT/', '$Q')" &
            PIDS[${k}]=$!
        done
        echo "iteration process ids: ${PIDS[*]}"
        for p in ${PIDS[*]}; do
            wait $p
        done
        unset PIDS
    done
    IFS=$OLDIFS
done
T2=$(timer $tmr)

if [[ "$T1" < "$T2" ]]; then
    echo "Passed: parallel time: $T1, sequential time: $T2"
else
    die "Failed: parallel time: $T1, sequential time: $T2"
fi
