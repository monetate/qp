#!/bin/bash

USER_AND_HOST=root@$DEVBOX

function run_test {
    echo "$1"
    $1 2>&1 1>/dev/null
    if [ $? ]; then
        echo -e "PASS\n"
    else
        echo -e "FAIL\n"
    fi
}

run_test "./tests/integration_test.sh $USER_AND_HOST" quiet
run_test "./tests/load_test.sh $USER_AND_HOST" quiet
