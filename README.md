# Query Parallelizer

## What it is

`qp` is a performance-boosting proxy for sharded MySQL databases. It recieves requests containing multiple queries, makes those queries in parallel, and returns the aggregated results. Requests are JSON formatted as an array of objects, each with a destination [DSN](http://en.wikipedia.org/wiki/Data_source_name) and query. Queries run in parallel for each request and requests are handled in parallel, for maximum concurrency.

An example request and response:

**Request**
```
[
  {
    "dsn": "root@tcp(127.0.0.1:20890)/product?charset=utf8",
    "query": "select pid, views from product_view order by rand() limit 2;"
  },
  {
    "dsn": "root@tcp(127.0.0.1:20891)/product?charset=utf8",
    "query": "select pid, views from product_view order by rand() limit 2;"
  },
  {
    "dsn": "root@tcp(127.0.0.1:20892)/product?charset=utf8",
    "query": "select pid, views from product_view order by rand() limit 2;"
  },
  {
    "dsn": "root@tcp(127.0.0.1:20893)/product?charset=utf8",
    "query": "select pid, views from product_view order by rand() limit 2;"
  }
]
```

**Response**
```
{
  "root@tcp(127.0.0.1:20890)/product?charset=utf8": [
    ["3732", 471], ["21017", 1737]
  ],
  "root@tcp(127.0.0.1:20891)/product?charset=utf8": [
    ["4111", 23098], ["16701", 23098]
  ],
  "root@tcp(127.0.0.1:20892)/product?charset=utf8": [
    ["2474", 273], ["22118", 1211]
  ],
  "root@tcp(127.0.0.1:20893)/product?charset=utf8": [
    ["2920", 415], ["25870", 1980]
  ]
}
```

**Note:** This response format implies that if a request contains multiple queries for the same DSNs, only one of the result sets will be returned per DSN, specifically the last one that is returned by that DSN. There may be a "tag" parameter in the future that would allow a request to contain multiple queries for the same database.

## Why it's different

Other shard-aggregating MySQL proxies include [Shard-Query](https://github.com/greenlion/swanhart-tools/tree/master/shard-query) and [Spock Proxy](http://spockproxy.sourceforge.net/). Both of these projects require an auxiliary MySQL database to be created and populated with shard configuration information. This is neccessary because these packages take a query with cross-shard predicates, and re-write the query internally for each shard. 

**This has a number of disadvantages:**

* The database-backed configuration is a hassle to create, operate, and maintain, and imposes limits on the sharded infrastructure that `qp` does not.
* Shard-key logic is limited to the options available in these packages. Removing this limitation was one of the main drivers behind creating `qp`: a database was sharded using a digest of multiple column values, and existing packages did not support this technique.
* The overhead of re-executing query-planning logic in these systems adds considerable overhead to each request, so much so that Shard-Query indicates that it is not meant for OLTP, with an expected minimum query time of 20ms.

**`qp` offers an alternative:**

* It is configuration free. Connection pools are opened to the first N DSNs that are requested, enabling one `qp` process to support many arbitrary pool configurations.
* Shard-key logic is offloaded to the client, which may even use `qp` to aggregate data from different schemas.
* `qp` does one thing and does it well, parallelize queries. Queries are not re-written so there is minimal service overhead.
* `qp` is meant to be used online for high-request-throughput workloads.

## Why it's fast

On startup, `qp` spawns a number of concurrent workers, each of which can make concurrent queries per request. Concurrent workers and queries are goroutines, not threads, which means that there is **no OS setup cost or context switching overhead in the concurrency model**. In fact, I/O syscalls made by goroutines are automatically multiplexed by Golang using the best available method on the system, e.g. [epoll on Linux or kqueue on BSD/OSX](https://groups.google.com/d/msg/golang-nuts/AQ8JOHxm9jA/cakNJj7_BVkJ). This means that Golang determines the appropraite number of "real" OS threads to use for parallel execution, while scheduling a collection of [coroutines](http://en.wikipedia.org/wiki/Coroutine) that it calls goroutines. To take advantage of performance enhancements to the Golang scheulder, **the latest version of Golang should be used. `qp` has been tested with Go version 1.4.2.**

As for MySQL connections, each time a request is made to a new DSN, a connection pool is opened to that server that is shared among all goroutines. Each connection pool has a limit on its number of connections.

## To Build

`make deps && make`

## To Test

`make test`

## To Run

`./qp `

**Options (with default argument shown, if any):**

**`-version`** print the version of `qp` and exit  
**`-url`** `tcp://127.0.0.1:9666` nanomsg URL to use for listening socket  
**`-workers`** `6` number of query workers  
**`-max_dsns`** `16` maximum number of DSNs for which to open a connection pool, once this limit is reached, queries cannot be made to any other DSN  

Example usage with all runtime options:

`./qp -url ipc:///tmp/qp.ipc -workers 64 -max_dsns 256`

