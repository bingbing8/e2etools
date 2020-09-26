namespace=$(kubectl get namespaces | awk '/horizontal-pod-autoscaling/{print $1}')
kubectl delete namespace $namespace