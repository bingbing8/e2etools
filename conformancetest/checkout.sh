        helpFunction()
        {
            echo ""
            echo "Usage: $0 -s subscriptionid -a clientappid -p clientappsecret -t tenantid -k kubeversion -i isolation"
            echo -e "\t-s azure subscription id"
            echo -e "\t-a client application id"
            echo -e "\t-s client secret"
            echo -e "\t-t tenant id"
            echo -e "\t-k kubernetes version"
            echo -e "\t-i isolation"
            exit 1 # Exit script after printing help
        }

        while getopts "s:a:p:t:k:" opt
        do
        echo "${opt}" "${OPTARG}"
        case "${opt}" in
            s ) subscriptionid=${OPTARG} ;;
            a ) clientappid=${OPTARG} ;;
            p ) clientappsecret=${OPTARG} ;;
            t ) tenantid=${OPTARG} ;;
            k ) kubeversion=${OPTARG} ;;
            i ) isolation=${OPTARG} ;;
            ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
        esac
        done

        export kubernetesversion=$kubeversion
        # download aks-engine
        curl -sSLf https://github.com/Azure/aks-engine/releases/download/v0.60.1/aks-engine-v0.60.1-linux-amd64.tar.gz > aks-engine.tar.gz
        mkdir -p aks-engine
        tar -zxvf aks-engine.tar.gz -C aks-engine --strip 1

	fileversion=${kubeversion//./_}
        set -x
        cp kubernetes_release_$(fileversion).json aks-engine/kubernetes_job_template.json
        pushd aks-engine
        AKS_ENGINE_PATH="$(pwd)"
  
        # Generate SSH keypair
        echo -e 'y\n' | ssh-keygen -f id_rsa -t rsa -N '' > /dev/null
        export SSH_PUBLIC_KEY="$(cat id_rsa.pub)"

        # Generate resource group name
        export RESOURCE_GROUP="k8s-${kubernetesversion}-$(isolation)-$(openssl rand -hex 3)"        


        ./aks-engine deploy \
          --dns-prefix ${RESOURCE_GROUP} \
          --resource-group ${RESOURCE_GROUP} \
          --api-model kubernetes_job_template.json \
          --location westus2 \
          --subscription-id $subscriptionid \
          --client-id $clientappid \
          --client-secret $clientappsecret

        export KUBECONFIG="$(pwd)/_output/${RESOURCE_GROUP}/kubeconfig/kubeconfig.westus2.json"

        # Wait for nodes and pods to become ready
        kubectl wait --for=condition=ready node --all
        kubectl wait pod -n kube-system --for=condition=Ready --all
        kubectl get nodes -owide
        kubectl cluster-info

        mkdir ${AKS_ENGINE_PATH}/logs

        curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list -o repo_list
        KUBE_TEST_REPO_LIST="$(pwd)/repo_list"
        git clone https://github.com/kubernetes/kubernetes --branch "release-${kubernetesversion}" --single-branch kubernetes
        pushd kubernetes

        make WHAT=cmd/kubectl
        make WHAT=test/e2e/e2e.test
        make ginkgo

        # setting this env prevents ginkg e2e from trying to run provider setup
        export KUBERNETES_CONFORMANCE_TEST="y"
        export GINKGO_PARALLEL_NODES="2"

        GINKGO_SKIP+="|\\[LinuxOnly\\]|Guestbook.application.should.create.and.stop.a.working.application"
        GINKGO_FOCUS="should.run.with.the.expected.status.\\[NodeConformance\\]"
        

        set -x
        ./hack/ginkgo-e2e.sh \
        '--provider=skeleton' \
        "--ginkgo.focus=${GINKGO_FOCUS}" "--ginkgo.skip=${GINKGO_SKIP}" \
        "--report-dir=${AKS_ENGINE_PATH}/logs" \
        '--disable-log-dump=true' "--node-os-distro=windows"

        dir ${AKS_ENGINE_PATH}/logs
        
         az login -u $clientappid -p $clientappsecret --service-principal --tenant $tenantid > /dev/null
         az account set -s $subscriptionid
         az group delete --name ${RESOURCE_GROUP} --yes --no-wait || true