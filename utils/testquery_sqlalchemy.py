#!/usr/bin/env python

import json
import requests
import sqlalchemy
from decimal import Decimal

query = "select 0.12345678901234567890;"
print "query:", query
print ''

print "# using qp"
qp_query = ("""{{
  "flat": true,
  "queries": [
    {{
      "dsn": "root@tcp(127.0.0.1:3306)/test",
      "query": "{query}"
    }}
  ]
}}""").format(query=query)
response = requests.post("http://127.0.0.1:9666", qp_query)
response = json.loads(response.text)
field_names = response[0]
field_types = response[1]
results = response[2:]
if "DecimalString" in field_types:
    indices = [i for i, x in enumerate(field_types) if x == "DecimalString"]
    for result in results:
        for i in indices:
            result[i] = Decimal(result[i])
print 'parsed response:', results
print ''

print "# using sqlalchemy"
engine = sqlalchemy.create_engine("mysql://root@localhost/test")
conn = engine.connect()
results = conn.execute(sqlalchemy.text(query))
print 'parsed response:', [r for r in results]
