kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/helpers/hyper-v-mutating-webhook/deployment.yaml
cat e2e-builder.template.yaml | envsubst | kubectl create -f -
kubectl logs -f e2e-builder
curl -OL https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/extensions/hyperv-mutating-webhook/v1/configure-hyperv-webhook.sh
chmod +x configure-hyperv-webhook.sh
./configure-hyperv-webhook.sh
rm configure-hyperv-webhook.sh