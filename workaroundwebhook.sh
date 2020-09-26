kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/helpers/hyper-v-mutating-webhook/deployment.yaml
kubectl get pod e2e-builder && kubectl delete pod e2e-builder || echo "e2e-builder does not exist"
cat e2e-builder.template.yaml | envsubst | kubectl create -f -
sleep 2m
kubectl logs -f e2e-builder
curl -OL https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/extensions/hyperv-mutating-webhook/v1/configure-hyperv-webhook.sh
chmod +x configure-hyperv-webhook.sh
./configure-hyperv-webhook.sh
rm configure-hyperv-webhook.sh