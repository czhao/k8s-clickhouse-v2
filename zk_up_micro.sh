NAMESPACE=$1
if [[ ! -z "$NAMESPACE" ]]; then
  NAMESPACE='--namespace='$NAMESPACE
else
  echo "usage: stack_up.sh <namespace>"
  exit
fi
kubectl create -f zookeeper_micro.yaml "$NAMESPACE"