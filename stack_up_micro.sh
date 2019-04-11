NAMESPACE=$1
if [[ ! -z "$NAMESPACE" ]]; then
  NAMESPACE='--namespace='$NAMESPACE
else
  echo "usage: stack_up_micro.sh <namespace>"
  exit
fi
while [ $(kubectl get po "$NAMESPACE" -o=wide | grep zk | grep Run | wc -l) -ne 1 ] ; do sleep 3; echo "Zookeper cluster not ready. Will try again after 3 sec..." ;done
kubectl create -f services_micro "$NAMESPACE"
kubectl create -f statefulsets_micro "$NAMESPACE"
