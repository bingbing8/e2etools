curl https://k8swin.blob.core.windows.net/k8s-windows/kubetest -o $K8S_ROOT/kubetest
chmod +x $K8S_ROOT/kubetest
export KUBE_TEST_REPO_LIST=/tmp/repo_list
curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list -o $KUBE_TEST_REPO_LIST
kubectl get pod e2e-builder && kubectl delete pod e2e-builder || echo "e2e-builder does not exist"
cat e2e-builder.template.yaml | envsubst | kubectl create -f -
sleep 2m
kubectl logs -f e2e-builder
export KUBECONFIG=~/.kube/config
cd ${K8S_ROOT}/kubernetes
