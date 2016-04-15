#!/usr/bin/env python

import requests
import sys
import json

if len(sys.argv) < 2:
    print "provide a path to a json file containing a qp query"
    sys.exit(1)

res = requests.post("http://127.0.0.1:9666", open(sys.argv[1]).read())
print 'text response: ', res.text
print 'python parsed response: ', json.loads(res.text)
