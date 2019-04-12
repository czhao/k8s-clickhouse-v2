# Introduction
This project demonstrate how to deploy a clickhouse cluster with persistent volume. 

# Preparation 
You may need to set up the persistent volume before proceeding to deploy clickhouse stack. 
```
cd pv
kubectl apply -f ch_pv_0.yaml
kubectl apply -f ch_pv_1.yaml
```
You must set up the persistent volume so the pod can initialize the permission properly. 

Then start the zookeeper. 

```
bash zk_up_micro.sh [NAMESPACE]
```

# ClickHouse cluster for kubernetes
use **stack_up_micro.sh** to deploy a micro cluster with 1 master and 1 replica. Alternatively you may configure more persistent volumes to deploy the full cluster via **stack_up.sh**.

```
bash stack_up_micro.sh [NAMESPACE]
```

To stop the clickhouse pods. 

```
bash stack_down_micro.sh [NAMESPACE]
```

To stop the zookeeper. 

```
bash zk_down_micro.sh [NAMESPACE]
```

# Configuration Highlights

## Volume Persistence and Permission
Volume mount is the obvious solution to acquire the real persistence while Clickhouse requires dedicated user (clickhouse) to manage the storage which points to `/var/lib/clickhouse`. In this case, you must change the ownership of the mount directory `/var/lib/clickhouse` before the pod starts via `initContainers` in both **clickhouse-0.yaml** and **clickhouse-1.yaml**.
```
initContainers:
        - name: fix-owner
          image: busybox
          command: ["chown", "-R", "101:101", "/var/lib/clickhouse"]
          volumeMounts:
            - name: ch-pv-storage
              mountPath: /var/lib/clickhouse
```

The owner 101 and group 101 is in use as it is the same uid/gid when the docker runs. You can find out via 
```
docker run -it xds2000/clickhouse-server /bin/bash id

clickhouse@f88e2b0ba967:/$ id
uid=101(clickhouse) gid=101(clickhouse) groups=101(clickhouse)

```

## Testing
Use port forwarding to use the k8s service as local service. 
```
kubectl port-forward svc/clickhouse-ext 9000:9000
```
Since 9000 is the default port for clickhouse-client. Then you can simply fire up clickhouse-client to use the service. 

```
➜  clickhouse git:(master) ✗ clickhouse-client
ClickHouse client version 19.4.3.11.
Connecting to localhost:9000 as user default.
Connected to ClickHouse server version 18.14.13 revision 54409.

clickhouse-1-0.clickhouse-1.default.svc.cluster.local :) 

```
For replica testing, create the table with distributed engine. 

```
CREATE TABLE ontime
(
    Year UInt16,
    Quarter UInt8,
    Month UInt8,
    DayofMonth UInt8,
    DayOfWeek UInt8,
    FlightDate Date,
    UniqueCarrier FixedString(7),
    AirlineID Int32,
    Carrier FixedString(2),
    TailNum String,
    FlightNum String,
    ....
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/flight', '{replica}')
PARTITION BY (FlightDate, Year)
ORDER BY (Year, FlightDate)
SAMPLE BY (FlightDate)

```

## Benchmark

### Data
use part of the [ontime dataset](https://clickhouse.yandex/docs/en/getting_started/example_datasets/ontime/) for benchmark testing. 
- 2GB raw data with 78 individual files
- 17GB uncompressed data
- 39201182 rows and 109 fields

For detail testing, please refer to [data/list.txt](data/list.txt)

### Configuratoin
- Micro setup with 2 replica
- 10GB PV 

### Import the data into clickhouse
```bash
for i in *.csv; do sed 's/\.00//g' $i | clickhouse-client --host=localhost --query="INSERT INTO ontime FORMAT CSVWithNames";  done;
```

### Performance Metrics
| Description | SQL | 耗时 |
|-------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| Import | N.A. | 260.84s user 31.66s system 71% cpu 6:46.86 total |
|  | select avg(c1) from (select Year, Month, count(*) as c1 from ontime group by Year, Month); | 1 rows in set. Elapsed: 0.473 sec. Processed 39.20 million rows, 117.60 MB (82.79 million rows/s., 248.37 MB/s.) |
|  | SELECT DayOfWeek, count(*) AS c FROM ontime WHERE Year >= 2001 AND Year <= 2018 GROUP BY DayOfWeek ORDER BY c DESC; | 7 rows in set. Elapsed: 0.379 sec. Processed 39.20 million rows, 117.60 MB (103.49 million rows/s., 310.48 MB/s.) |
|  | SELECT DayOfWeek, count(*) AS c FROM ontime WHERE DepDelay>10 AND Year >= 2000 AND Year <= 2018 GROUP BY DayOfWeek ORDER BY c DESC | 7 rows in set. Elapsed: 0.715 sec. Processed 39.20 million rows, 181.85 MB (54.86 million rows/s., 254.50 MB/s.) |
|  | SELECT Origin, count(*) AS c FROM ontime WHERE DepDelay>10 AND Year >= 2000 AND Year <= 2018 GROUP BY Origin ORDER BY c DESC LIMIT 10 | 10 rows in set. Elapsed: 1.161 sec. Processed 39.20 million rows, 215.26 MB (33.76 million rows/s., 185.37 MB/s.) |
|  | SELECT Carrier, count(*) FROM ontime WHERE DepDelay>10 AND Year = 2016 GROUP BY Carrier ORDER BY count(*) DESC | 12 rows in set. Elapsed: 0.126 sec. Processed 5.62 million rows, 26.93 MB (44.55 million rows/s., 213.57 MB/s.) |
|  | SELECT Carrier, c, c2, c*1000/c2 as c3 FROM (     SELECT         Carrier,         count(*) AS c     FROM ontime     WHERE DepDelay>10         AND Year=2016     GROUP BY Carrier ) ANY INNER JOIN (     SELECT         Carrier,         count(*) AS c2     FROM ontime     WHERE Year=2016     GROUP BY Carrier ) USING Carrier ORDER BY c3 DESC; | 12 rows in set. Elapsed: 0.389 sec. Processed 11.24 million rows, 49.41 MB (28.89 million rows/s., 127.05 MB/s.) |
|  | SELECT DestCityName, uniqExact(OriginCityName) AS u FROM ontime WHERE Year >= 2000 and Year <= 2018 GROUP BY DestCityName ORDER BY u DESC LIMIT 10; | 10 rows in set. Elapsed: 1.086 sec. Processed 39.20 million rows, 1.81 GB (36.08 million rows/s., 1.66 GB/s.) |
|  | select    min(Year), max(Year), Carrier, count(*) as cnt,    sum(ArrDelayMinutes>30) as flights_delayed,    round(sum(ArrDelayMinutes>30)/count(*),2) as rate FROM ontime WHERE    DayOfWeek not in (6,7) and OriginState not in ('AK', 'HI', 'PR', 'VI')    and DestState not in ('AK', 'HI', 'PR', 'VI')    and FlightDate < '2019-01-01' GROUP by Carrier HAVING cnt > 100000 and max(Year) > 1990 ORDER by rate DESC LIMIT 1000; | 18 rows in set. Elapsed: 1.085 sec. Processed 39.20 million rows, 443.69 MB (36.14 million rows/s., 409.00 MB/s.) |


### Table Schema
```
CREATE TABLE ontime
(
    Year UInt16,
    Quarter UInt8,
    Month UInt8,
    DayofMonth UInt8,
    DayOfWeek UInt8,
    FlightDate Date,
    UniqueCarrier FixedString(7),
    AirlineID Int32,
    Carrier FixedString(2),
    TailNum String,
    FlightNum String,
    OriginAirportID Int32,
    OriginAirportSeqID Int32,
    OriginCityMarketID Int32,
    Origin FixedString(5),
    OriginCityName String,
    OriginState FixedString(2),
    OriginStateFips String,
    OriginStateName String,
    OriginWac Int32,
    DestAirportID Int32,
    DestAirportSeqID Int32,
    DestCityMarketID Int32,
    Dest FixedString(5),
    DestCityName String,
    DestState FixedString(2),
    DestStateFips String,
    DestStateName String,
    DestWac Int32,
    CRSDepTime Int32,
    DepTime Int32,
    DepDelay Int32,
    DepDelayMinutes Int32,
    DepDel15 Int32,
    DepartureDelayGroups String,
    DepTimeBlk String,
    TaxiOut Int32,
    WheelsOff Int32,
    WheelsOn Int32,
    TaxiIn Int32,
    CRSArrTime Int32,
    ArrTime Int32,
    ArrDelay Int32,
    ArrDelayMinutes Int32,
    ArrDel15 Int32,
    ArrivalDelayGroups Int32,
    ArrTimeBlk String,
    Cancelled UInt8,
    CancellationCode FixedString(1),
    Diverted UInt8,
    CRSElapsedTime Int32,
    ActualElapsedTime Int32,
    AirTime Int32,
    Flights Int32,
    Distance Int32,
    DistanceGroup UInt8,
    CarrierDelay Int32,
    WeatherDelay Int32,
    NASDelay Int32,
    SecurityDelay Int32,
    LateAircraftDelay Int32,
    FirstDepTime String,
    TotalAddGTime String,
    LongestAddGTime String,
    DivAirportLandings String,
    DivReachedDest String,
    DivActualElapsedTime String,
    DivArrDelay String,
    DivDistance String,
    Div1Airport String,
    Div1AirportID Int32,
    Div1AirportSeqID Int32,
    Div1WheelsOn String,
    Div1TotalGTime String,
    Div1LongestGTime String,
    Div1WheelsOff String,
    Div1TailNum String,
    Div2Airport String,
    Div2AirportID Int32,
    Div2AirportSeqID Int32,
    Div2WheelsOn String,
    Div2TotalGTime String,
    Div2LongestGTime String,
    Div2WheelsOff String,
    Div2TailNum String,
    Div3Airport String,
    Div3AirportID Int32,
    Div3AirportSeqID Int32,
    Div3WheelsOn String,
    Div3TotalGTime String,
    Div3LongestGTime String,
    Div3WheelsOff String,
    Div3TailNum String,
    Div4Airport String,
    Div4AirportID Int32,
    Div4AirportSeqID Int32,
    Div4WheelsOn String,
    Div4TotalGTime String,
    Div4LongestGTime String,
    Div4WheelsOff String,
    Div4TailNum String,
    Div5Airport String,
    Div5AirportID Int32,
    Div5AirportSeqID Int32,
    Div5WheelsOn String,
    Div5TotalGTime String,
    Div5LongestGTime String,
    Div5WheelsOff String,
    Div5TailNum String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/flight', '{replica}')
PARTITION BY (FlightDate, Year)
ORDER BY (Year, FlightDate)
SAMPLE BY (FlightDate)

```






