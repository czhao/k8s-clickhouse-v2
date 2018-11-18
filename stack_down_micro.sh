NAMESPACE=$1
if [[ ! -z "$NAMESPACE" ]]; then
  NAMESPACE='--namespace='$NAMESPACE
else
  echo "usage: stack_down.sh <namespace>"
  exit
fi

kubectl delete -f zookeeper_micro.yaml "$NAMESPACE"
kubectl delete -f statefulsets_micro "$NAMESPACE"
kubectl delete -f services_micro "$NAMESPACE"
