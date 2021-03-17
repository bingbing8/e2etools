#!/bin/bash

helpFunction()
{
    echo ""
    echo "Usage: $0 -s subscriptionid -a clientappid -p clientappsecret -t tenantid -k kubeversion -o isolation -c storageaccountkey"
    echo -e "\t-s azure subscription id"
    echo -e "\t-a client application id"
    echo -e "\t-p client secret"
    echo -e "\t-t tenant id"
    echo -e "\t-k kubernetes version"
    echo -e "\t-o isolation"
    echo -e "\t-c storage account key"
    exit 1 # Exit script after printing help
}

while getopts "s:a:p:t:k:o:c:" opt
do
echo "${opt}" "${OPTARG}"
case "${opt}" in
    s ) subscriptionid=${OPTARG} ;;
    a ) clientappid=${OPTARG} ;;
    p ) clientappsecret=${OPTARG} ;;
    t ) tenantid=${OPTARG} ;;
    k ) kubeversion=${OPTARG} ;;
    o ) isolation=${OPTARG} ;;
    c ) storageaccountkey=${OPTARG} ;;
    ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
esac
done
set -eux -o pipefail
export Kubernetes_Version=$kubeversion
# download aks-engine
curl -sSLf https://aka.ms/ContainerPlatTest/aks-engine-linux-amd64.tar.gz > aks-engine.tar.gz
mkdir -p aks-engine
tar -zxvf aks-engine.tar.gz -C aks-engine --strip 1

export File_Version="${kubeversion//./_}"
cp kubernetes.json aks-engine/kubernetes.json
pushd aks-engine
export AKS_ENGINE_PATH="$(pwd)"

# Generate SSH keypair, but not used it for now
echo -e 'y\n' | ssh-keygen -f id_rsa -t rsa -N '' > /dev/null

# use publid key from 
scriptdir=`dirname "${BASH_SOURCE}"`
echo 'here'
export SSH_PUBLIC_KEY="$(cat ${scriptdir}/rsapub.pub)"
echo 'done'

# Generate resource group name
export RESOURCE_GROUP="k8s-${kubeversion//.}-$isolation-$(openssl rand -hex 3)"   
export CONTAINER_NAME=${RESOURCE_GROUP}       
echo "##vso[task.setvariable variable=logcontainername]${CONTAINER_NAME}"

az storage container create -n ${CONTAINER_NAME} --account-name cirruscontainerplat --account-key $storageaccountkey
az storage blob upload --account-name cirruscontainerplat --account-key $storageaccountkey --container-name ${CONTAINER_NAME} --file ${AKS_ENGINE_PATH}/id_rsa --name id_rsa

./aks-engine deploy \
  --dns-prefix ${RESOURCE_GROUP} \
  --resource-group ${RESOURCE_GROUP} \
  --api-model kubernetes.json \
  --location westus2 \
  --subscription-id $subscriptionid \
  --client-id $clientappid \
  --client-secret $clientappsecret \
  

export KUBECONFIG="$(pwd)/_output/${RESOURCE_GROUP}/kubeconfig/kubeconfig.westus2.json"

# Wait for nodes and pods to become ready
kubectl wait --for=condition=ready node --all
kubectl wait pod -n kube-system --for=condition=Ready --all
kubectl get nodes -owide
kubectl cluster-info

# az network public-ip list -g ${RESOURCE_GROUP} --output table

mkdir ${AKS_ENGINE_PATH}/logs
echo "##vso[task.setvariable variable=workingfolder]${AKS_ENGINE_PATH}"

curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list -o repo_list
export KUBE_TEST_REPO_LIST="$(pwd)/repo_list"
git clone https://github.com/kubernetes/kubernetes --branch "release-${Kubernetes_Version}" --single-branch kubernetes
pushd kubernetes

make WHAT=cmd/kubectl
make WHAT=test/e2e/e2e.test
make ginkgo

# setting this env prevents ginkg e2e from trying to run provider setup
export KUBERNETES_CONFORMANCE_TEST="y"
export GINKGO_PARALLEL_NODES="2"

export GINKGO_SKIP="\\[LinuxOnly\\]|\\[Serial\\]|GMSA|Guestbook.application.should.create.and.stop.a.working.application"
export GINKGO_FOCUS="\\[Conformance\\]|\\[NodeConformance\\]|\\[sig-windows\\]|\\[sig-apps\\].CronJob|\\[sig-api-machinery\\].ResourceQuota|\\[sig-scheduling\\].SchedulerPreemption|\\[sig-autoscaling\\].\\[Feature:HPA\\]"
#export GINKGO_FOCUS="\\[sig-storage\\].EmptyDir.volumes.pod.should.support.shared.volumes.between.containers.\\[Conformance\\]"

./hack/ginkgo-e2e.sh \
'--provider=skeleton' \
"--ginkgo.focus=${GINKGO_FOCUS}" "--ginkgo.skip=${GINKGO_SKIP}" \
"--report-dir=${AKS_ENGINE_PATH}/logs" \
'--disable-log-dump=true' "--node-os-distro=windows"

dir ${AKS_ENGINE_PATH}/logs
az storage blob upload-batch --account-name cirruscontainerplat --account-key $storageaccountkey -d ${CONTAINER_NAME} -s  ${AKS_ENGINE_PATH}/logs

az login -u $clientappid -p $clientappsecret --service-principal --tenant $tenantid > /dev/null
az account set -s $subscriptionid
az group delete --name ${RESOURCE_GROUP} --yes --no-wait || true