NAMESPACE=$1
if [[ ! -z "$NAMESPACE" ]]; then
  NAMESPACE='--namespace='$NAMESPACE
else
  echo "usage: zk_down_micro.sh <namespace>"
  exit
fi

kubectl delete -f zookeeper_micro.yaml "$NAMESPACE"