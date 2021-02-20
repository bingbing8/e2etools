        helpFunction()
        {
            echo ""
            echo "Usage: $0 -s subscriptionid -a clientappid -p clientappsecret"
            echo -e "\t-s azure subscription id"
            echo -e "\t-a client application id"
            echo -e "\t-p client secret"
            exit 1 # Exit script after printing help
        }

        while getopts "s:a:p:" opt
        do
        echo "${opt}" "${OPTARG}"
        case "${opt}" in
            s ) subscriptionid=${OPTARG} ;;
            a ) clientappid=${OPTARG} ;;
            p ) clientappsecret=${OPTARG} ;;
            ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
        esac
        done

        echo "$subscriptionid"
        echo "$clientappid"
        echo "$clientappsecret"

        # download aks-engine
        curl -sSLf https://github.com/Azure/aks-engine/releases/download/v0.60.1/aks-engine-v0.60.1-linux-amd64.tar.gz > aks-engine.tar.gz
        mkdir -p aks-engine
        tar -zxvf aks-engine.tar.gz -C aks-engine --strip 1

        set -x
        pushd aks-engine

        # Generate SSH keypair
        echo -e 'y\n' | ssh-keygen -f id_rsa -t rsa -N '' > /dev/null
        export SSH_PUBLIC_KEY="$(cat id_rsa.pub)"

        # Generate resource group name
        export RESOURCE_GROUP="moby-containerd-e2e-$(openssl rand -hex 3)"
        echo "##vso[task.setvariable variable=RESOURCE_GROUP]${RESOURCE_GROUP}"


        curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/job-templates/kubernetes_release_1_20.json > kubernetes_release_1_20.json

        ./aks-engine deploy \
          --dns-prefix ${RESOURCE_GROUP} \
          --resource-group ${RESOURCE_GROUP} \
          --api-model kubernetes_release_1_20.json \
          --location westus2 \
          --subscription-id $subscriptionid \
          --client-id $clientappid \
          --client-secret $clientappsecret

        export KUBECONFIG="$(pwd)/aks-engine/_output/${RESOURCE_GROUP}/kubeconfig/kubeconfig.westus2.json"
        echo "##vso[task.setvariable variable=KUBECONFIG]${KUBECONFIG}"

        # Wait for nodes and pods to become ready
        kubectl wait --for=condition=ready node --all
        kubectl wait pod -n kube-system --for=condition=Ready --all
        kubectl get nodes -owide
        kubectl cluster-info


        curl https://raw.githubusercontent.com/kubernetes-sigs/windows-testing/master/images/image-repo-list -o repo_list
        KUBE_TEST_REPO_LIST="$(pwd)/repo_list"
        echo "##vso[task.setvariable variable=KUBE_TEST_REPO_LIST]${KUBE_TEST_REPO_LIST}"

        git clone https://github.com/kubernetes/kubernetes --branch $(kubectl get no -ojson | jq -r ".items[0].status.nodeInfo.kubeletVersion") --single-branch kubernetes
