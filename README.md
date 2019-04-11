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

# ClickHouse cluster for kubernetes
use **stack_up_micro.sh** to deploy a micro cluster with 1 master and 1 replica. Alternatively you may configure more persistent volumes to deploy the full cluster via **stack_up.sh**.

```
bash stack_up_micro.sh
```

To stop the instance. 

```
bash stack_down_micro.sh
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






