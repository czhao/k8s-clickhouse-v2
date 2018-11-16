#!/bin/bash

echo "Building Image processing..."

docker build -t xds2000/clickhouse-server -f Dockerfile.micro .
