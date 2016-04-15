#!/bin/bash

# Test for correct behavior.
# This does not test performance.


GOPATH=`pwd`/.go

PORT=9666
URL=:$PORT

TEST_DB="qp_test_database"
PID=-1
SSH_TUNNEL_PID=-1

function die()
{
    echo $1
    shutdown
    echo "FAIL"
    exit 666
}

MYSQL_HOST=$1
if [ "$MYSQL_HOST" == "" ]; then
    echo "Please supply username@hostname for MySQL tunnels"
    exit 666
fi


function create_test_database()
{
    mysql --host=127.0.0.1 --user=root --port=22890 -e "drop database if exists qp_test_database;"
    mysqladmin --host=127.0.0.1 --port=22890 -u root create $TEST_DB
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "drop table if exists test;"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "create table test(id int, type varchar(64), value varchar(64));"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(1, 'A', '123');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(2, 'B', '123');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(3, 'C', '123');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(4, 'D', '456');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(5, 'E', '456');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(6, 'F', '456');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(7, 'G', '456');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(8, 'H', '567');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(9, 'I', '567');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(10, 'J', '567');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(11, 'K', '567');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(12, 'L', '678');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(13, 'M', '678');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(14, 'N', '678');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(15, 'O', '678');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(16, 'P', '789');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(17, 'Q', '789');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(18, 'R', '789');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(19, 'S', '789');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(20, 'T', '890');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(21, 'U', '890');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(22, 'V', '890');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(23, 'W', '890');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(24, 'X', '234');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(25, 'Y', '234');"
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(26, 'Z', '234');"
    
    mysql --host=127.0.0.1 --user=root --port=22890 $TEST_DB -e "insert into test values(100, NULL, '999');"
    echo "created test database"
}

function create_local_tunnels()
{
    ip=127.0.0.1
    ssh -Nn -L 22890:$ip:3306 -L 22891:$ip:3306 -L 22892:$ip:3306 -L 22893:$ip:3306 $MYSQL_HOST &
    SSH_TUNNEL_PID=$!
    # wait for tunnel to be established
    while $(netstat -anp tcp | awk '$6 == "LISTEN" && $4 ~ "\.22890"') > /dev/null 2>&1; do
        echo "Waiting for tunnel to be up..."
        sleep 0.5
    done
    echo "Tunnel is up."
}

QUET=$2
function create_qp()
{
    PROCESS=./qp
    MAX_DSNS=8
    if [ QUIET ]; then
        $PROCESS -url $URL -maxDsns=$MAX_DSNS -maxConnsPerDsn=24 2>&1 1>/dev/null &
    else
        $PROCESS -url $URL -maxDsns=$MAX_DSNS -maxConnsPerDsn=24 &
    fi
    PID=$!
    sleep 2
}

function startup()
{
    echo "starting up"
    create_local_tunnels
    create_test_database
    create_qp
}

function shutdown()
{
    echo "shutting down"
    kill $SSH_TUNNEL_PID
    kill $PID
}

function single_query_test()
{
    Q="{\"flat\":true,\"queries\":[{\"dsn\":\"root@tcp(127.0.0.1:22890)/$TEST_DB?charset=utf8\",\"query\":\"select type from test where value=\\\\\"234\\\\\" order by type\"}]}"
    EXPECTED='[["type"],["NullString"],["X"],["Y"],["Z"]]'
    RESPONSE=$(python -c "import requests; print requests.post('http://localhost:$PORT/', '$Q').text")
    if [ "$RESPONSE" != "$EXPECTED" ]; then
        die "single_query_test bad response: $RESPONSE, expected $EXPECTED"
    fi
    echo "single_query_test: pass"
}

function multi_query_test()
{
    Q1="{\"dsn\":\"root@tcp(127.0.0.1:22890)/$TEST_DB?charset=utf8\",\"query\":\"select type from test where value=\\\\\"234\\\\\"\"}"
    Q2="{\"dsn\":\"root@tcp(127.0.0.1:22891)/$TEST_DB?charset=utf8\",\"query\":\"select type from test where value=\\\\\"234\\\\\"\"}"
    Q="{\"flat\":true,\"queries\":[$Q1,$Q2]}"
    EXPECTED='[["type"],["NullString"],["X"],["Y"],["Z"],["X"],["Y"],["Z"]]'
    RESPONSE=$(python -c "import requests; print requests.post('http://localhost:$PORT/', '$Q').text")
    if [ "$RESPONSE" != "$EXPECTED" ]; then
        die "multi_query_test bad response: $RESPONSE, expected $EXPECTED"
    fi
    echo "multi_query_test: pass"
}

function multi_query_mixed_test()
{
    Q1="{\"dsn\":\"root@tcp(127.0.0.1:22890)/$TEST_DB?charset=utf8\",\"query\":\"select type from test where value=\\\\\"234\\\\\"\"}"
    Q2="{\"dsn\":\"root@tcp(127.0.0.1:22891)/$TEST_DB?charset=utf8\",\"query\":\"select type from test where value=\\\\\"123\\\\\"\"}"
    Q="{\"flat\":false,\"queries\":[$Q1,$Q2]}"
    EXPECTED1='[["X"],["Y"],["Z"]]'
    EXPECTED2='[["A"],["B"],["C"]]'
    RESPONSE=$(python -c "import requests; print requests.post('http://localhost:$PORT/', '$Q').text")
    DATA1=$(echo $RESPONSE | jq -a -c '."root@tcp(127.0.0.1:22890)/'$TEST_DB'?charset=utf8"')
    DATA2=$(echo $RESPONSE | jq -a -c '."root@tcp(127.0.0.1:22891)/'$TEST_DB'?charset=utf8"')    
    if [ "$DATA1" != "$EXPECTED1" ]; then
        die "multi_query_mixed_test bad response: $DATA1, expected $EXPECTED1"
    fi
    if [ "$DATA2" != "$EXPECTED2" ]; then
        die "multi_query_mixed_test bad response: $DATA2, expected $EXPECTED2"
    fi
    echo "multi_query_mixed_test: pass"
}

function null_value_test()
{
    Q="{\"flat\":false,\"queries\":[{\"dsn\":\"root@tcp(127.0.0.1:22890)/$TEST_DB?charset=utf8\",\"query\":\"select type from test where value=\\\\\"999\\\\\"\"}]}"
    EXPECTED='[[null]]'
    RESPONSE=$(python -c "import requests; print requests.post('http://localhost:$PORT/', '$Q').text")
    DATA=$(echo $RESPONSE | jq -a -c '."root@tcp(127.0.0.1:22890)/'$TEST_DB'?charset=utf8"')    
    if [ "$DATA" != "$EXPECTED" ]; then
        die "null_value_test bad response: $DATA, expected $EXPECTED"
    fi
    echo "null_value_test: pass"
}

function run_tests()
{    
    single_query_test
    null_value_test
    multi_query_test
    multi_query_mixed_test
}

function handle_interrupt()
{
    die "interrupted"
}

trap 'handle_interrupt' HUP INT QUIT TERM ERR

startup
run_tests
shutdown
echo "SUCCESS"
