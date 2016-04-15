package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"github.com/arnehormann/sqlinternals/mysqlinternals"
	_ "github.com/go-sql-driver/mysql"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"reflect"
	"regexp"
	"sync"
	"syscall"
	"time"
	_ "net/http/pprof"
	"runtime/debug"
)

// globals
// constants
const DECIMAL_AS_STRING = true
// configuration
var version string // NOTE: supplied automatically via Makefile
var debugLog bool
var maxDsns int
var maxConnsPerDsn int
var heapDumpDir string
// data
var dbs = make(map[string]*sql.DB)
var dbsMutex = &sync.Mutex{}

func dbFromDsn(dsn string) (db *sql.DB, err error) {
	// If the connections for this DSN are cached, return them
	dbsMutex.Lock()
	defer dbsMutex.Unlock()
	dbi, ok := dbs[dsn]
	if ok {
		return dbi, nil
	}
	if len(dbs)+1 > maxDsns {
		return nil, errors.New("dsn cache full")
	}
	dbc, err := sql.Open("mysql", dsn)
	if err != nil {
		log.Printf("Error initializing database connection: %s\n", err.Error())
		return nil, err
	}
	dbc.SetMaxIdleConns(maxConnsPerDsn)
	dbc.SetMaxOpenConns(maxConnsPerDsn)
	dbs[dsn] = dbc
	return dbc, nil
}

func flattenNullable (writeCols []interface{}) {
	// change nullable structs into values or nil
	for i, intf := range (writeCols) {
		kind := reflect.TypeOf(intf).Elem().Kind()

		// if the value scanned into a struct, it was nullable
		if (kind != reflect.Struct) {
			continue
		}

		valid := reflect.ValueOf(intf).Elem().FieldByName("Valid").Bool()
		if (valid) {
			// if it was nullable and not null, we just want the value
			nintf := reflect.ValueOf(intf).Elem().FieldByIndex([]int{0}).Interface()
			writeCols[i] = nintf
		} else {
			// if it was nullable and null, we want nil
			writeCols[i] = nil
		}
	}
}

type dsnResults struct {
	dsn string
	header []interface{}
	types []interface{}
	records [][]interface{}
}

func runQuery(dsn string, query string, results chan<- dsnResults) {
	var res dsnResults
	res.dsn = dsn
	defer func() {results <- res}()

	// get the specified database handle
	db, err := dbFromDsn(dsn)
	if err != nil {
		log.Printf("Error finding database (%s): %s\n", cleanNameFromDsn(dsn), err.Error())
		return
	}

	// execte the query
	if debugLog {
		log.Printf("Querying %s: %s\n", cleanNameFromDsn(dsn), query)
	}
	rows, err := db.Query(query)
	if err != nil {
		log.Printf("Error querying database: %s\n", err.Error())
		return
	}

	// get MySQL column information for interface types
	type DecimalString string;
	DecimalStringType := reflect.TypeOf(DecimalString(""));
	StringType := reflect.TypeOf(string(""));

	columns, err := mysqlinternals.Columns(rows)
	if err != nil {
		log.Printf("Error inspecting column types: %s\n", err.Error())
		return
	}
	sqlTypes := make([]reflect.Type, len(columns))
	for i, _ := range sqlTypes {
		res.header = append(res.header, columns[i].Name())
		sqlType, err := columns[i].ReflectSqlType(true)
		if err != nil {
			if DECIMAL_AS_STRING && columns[i].IsDecimal() {
				sqlType = DecimalStringType
			} else {
				log.Printf("Error creating storage for column type: %s\n", err.Error())
				return
			}
		}
		sqlTypes[i] = sqlType
		res.types = append(res.types, sqlType.Name())
	}

	// store the result set
	readCols := make([]interface{}, len(columns))
	writeCols := make([]interface{}, len(columns))
	for rows.Next() {
		for i, sqlType := range sqlTypes {
			if sqlType == DecimalStringType {
				/* This allows us to scan into a string,
				   but leave "DecimalString" in the type list */
				sqlType = StringType
			}
			writeCols[i] = reflect.New(sqlType).Interface()
			readCols[i] = writeCols[i]
		}
		err := rows.Scan(readCols...)
		if err != nil {
			log.Printf("Error scanning result record: %s\n", err.Error())
			results <- res
			return
		}

		flattenNullable(writeCols)

		outCols := make([]interface{}, len(columns))
		copy(outCols, writeCols)
		res.records = append(res.records, outCols)
	}

	// return the results
	return
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	resultsChan := make(chan dsnResults)

	// parse queries
	type DsnQuery struct {
		Dsn   string
		Query string
	}
	type Request struct {
		Flat bool
		Queries []DsnQuery
	}
	var req Request

	decoder := json.NewDecoder(r.Body)
	err := decoder.Decode(&req)
	if err != nil {
		log.Printf("Error decoding json: %s\n", err.Error())
		w.WriteHeader(500)
		return
	}

	queries := req.Queries
	if len(queries) == 0 {
		log.Printf("No queries requested\n")
		w.WriteHeader(500)
		return
	}

	// execute queries in parallel
	for i := range queries {
		go runQuery(queries[i].Dsn, queries[i].Query, resultsChan)
	}

	// aggregate responses
	var allResults []dsnResults
	for _ = range queries {
		allResults = append(allResults, <-resultsChan)
	}

	type flatResults [][]interface{}
	type mappedResults map[string][][]interface{}

	// map results to dsn names
	var results interface{}
	if req.Flat {
		results = make(flatResults, 2)
		results.(flatResults)[0] = allResults[0].header
		results.(flatResults)[1] = allResults[0].types
		for _, dsnRes := range allResults {
			results = append(results.(flatResults), dsnRes.records...)
		}
	} else {
		results = make(mappedResults)
		for _, dsnRes := range allResults {
			results.(mappedResults)[dsnRes.dsn] = dsnRes.records
		}
	}

	// send responses
	res, _ := json.Marshal(results)

	// send responses
	log.Printf("Sending %d responses to %d queries\n", len(allResults), len(queries))
	if debugLog {
		log.Printf("Response: %s\n", res)
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(res)
}

func cleanNameFromDsn(dsn string) (cleanName string) {
	re := regexp.MustCompile(".+@(.+)/(.+)\\??.*")
	nameParts := re.FindStringSubmatch(dsn)
	if nameParts != nil {
		cleanName = fmt.Sprintf("%s/%s", nameParts[1], nameParts[2])
	} else {
		cleanName = "<Couldn't parse host/database>"
	}
	return cleanName
}

func closeAll() {
	dbsMutex.Lock()
	defer dbsMutex.Unlock()
	for dsn, db := range dbs {
		log.Println("Closing:", dsn)
		db.Close()
	}
}

func signalHandler(s chan os.Signal) {
	for {
		sig := <-s
		log.Println("We get signal:", sig)
		if sig.String() == "user defined signal 1" {
			// dump heap to a file when USR1 is received
			filename := fmt.Sprintf("qp-heapdump-%d", time.Now().Unix())
			filepath := heapDumpDir + filename
			log.Printf("dumping heap to %s\n", filepath)
			f, err := os.Create(filepath)
			if err != nil {
				log.Printf("Couldn't open file for writing\n")
			} else {
				debug.WriteHeapDump(f.Fd())
			}
		} else {
			closeAll()
			os.Exit(1)
		}
	}
}

func main() {
	var versionFlag = flag.Bool("version", false, "print version")
	var dsnsFlag = flag.Int("maxDsns", 16, "maximum number of cached dsns")
	var connsFlag = flag.Int("maxConnsPerDsn", 24, "maximum number of connections per dsn")
	var socketFlag = flag.String("url", ":9666", "the socket url to listen to")
	var debugFlag = flag.Bool("debug", false, "log debug information")
	var heapDumpDirFlag = flag.String("heapDumpDir", "/mnt/tmp/", "directory in which to dump heap")
	flag.Parse()
	if *versionFlag {
		fmt.Println(version)
		os.Exit(0)
	}
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, os.Kill, syscall.SIGUSR1)
	go signalHandler(c)

	socketUrl := *socketFlag
	maxDsns = *dsnsFlag
	maxConnsPerDsn = *connsFlag
	debugLog = *debugFlag
	heapDumpDir = *heapDumpDirFlag
	rand.Seed(time.Now().UnixNano())

	log.Printf("version:%s socket:%s maxDsns:%d debug:%t heapDumpDir:%s\n",
	           version, socketUrl, maxDsns, debugLog, heapDumpDir)

	http.HandleFunc("/", handleRequest)
	err := http.ListenAndServe(socketUrl, nil)
	if err != nil {
		log.Fatal("Can't serve: ", err)
	}
	closeAll()
	os.Exit(0)
}
