#!/bin/bash

# set -x
export GOPROXY='direct'

ACCOUNT=$1
REGION=$2
CLUSTER=$3
SIGNER_NAME=${4:-'my-private-signer.com/my-signer'}
AL2=$5
ESCAPED_SIGNER_NAME=${SIGNER_NAME/\//\\\/}

ACCOUNT_REGEX='^[0-9]{12}$'
REGION_REGEX='^[a-zA-Z0-9-]{1,128}$'

signer_already_installed(){
    kubectl get ns signer-ca-system 2>&1 > /dev/null
    return $?
}

gmsa_already_installed(){
    kubectl get ns gmsa-webhook 2>&1 > /dev/null
    return $?
}

deleting_existing_gmsa(){

    echo 'Deleting existing gMSA installation'
    kubectl delete clusterrole gmsa-webhook-gmsa-webhook-rbac-role
    kubectl delete clusterrolebinding gmsa-webhook-gmsa-webhook-binding-to-gmsa-webhook-gmsa-webhook-rbac-role
    kubectl delete deployment gmsa-webhook -n gmsa-webhook
    kubectl delete service gmsa-webhook -n gmsa-webhook
    kubectl delete ValidatingWebhookConfiguration gmsa-webhook
    kubectl delete MutatingWebhookConfiguration gmsa-webhook
    kubectl delete ns gmsa-webhook

}

test_command(){

    $@ > /dev/null 2>&1
    if [ $? == '127' ]
    then
        return 1
    else
        return 0
    fi
}

run_al2_prereq_installation(){

    if [[ $1 ]]
    then
        echo "Installing Amazon Linux 2 dependencies"
        bash ./AL2-dependency-installation.sh
    fi
}

validate_regex(){
    PARAMETER=$1
    REGEX=$2
    [[ $PARAMETER =~ $REGEX ]] && return 0 || return 1
    return $?
}
validate_account(){
    ACCOUNT=$1
    validate_regex $ACCOUNT $ACCOUNT_REGEX
    return $?
}
validate_region(){
    REGION=$1
    validate_regex $REGION $REGION_REGEX
    return $?
}
validate_AL2(){
    [[ '$1' != 'AL2' ]] && return 0 || return 1
}
validate_parameters(){

    validate_account $ACCOUNT
    if [[ $? -eq 0 ]]
    then 
        echo "Valid Account. Proceeding"
    else
        echo "Invalid Account. Aborting"
        exit 1
    fi
    validate_region $REGION
    if [[ $? -eq 0 ]]
    then
        echo "Valid region. Proceeding"
    else
        echo "Invalid region. Aborting"
        exit 1
    fi
    if [ -n $AL2 ]
    then
        validate_AL2 $AL2
        if [[ $? -eq 0 ]]
        then
            echo "Valid OS parameter. Proceeding"
        else
            echo "Invalid OS parameter. Aborting"
            exit 1
        fi
    fi
    
}

#CHECKING PARAMETERS
validate_parameters
run_al2_prereq_installation $AL2
#____________PERFORMING CHECKS
AWS_CLI="aws --version"
if  ! test_command $AWS_CLI;
then
    echo "AWS binary not installed. Please install it before running this script."
    exit 1
fi
DOCKER="docker ps"
if ! test_command $DOCKER;
then
    echo "Docker daemon not running. Please make sure it's running it before executing this script."
    exit 1
fi
CFSSL="cfssl version"
if ! test_command $CFSSL;
then
    echo "cfssl binary not installed. Please install it before running this script."
    exit 1
fi
CFSSLJSON="cfssljson -version"
if ! test_command $CFSSLJSON;
then
    echo "cfssljson binary not installed. Please install it before running this script."
    exit 1
fi
KUSTOMIZE="kustomize version"
if ! test_command $KUSTOMIZE;
then
    echo "kustomize binary not installed. Please install it before running this script."
    exit 1
fi
GIT="git version"
if ! test_command $GIT;
then
    echo "git binary not installed. Please install it before running this script."
    exit 1
fi
KUBECTL="kubectl version"
if ! test_command $KUBECTL;
then
    echo "kubectl binary not installed. Please install it before running this script."
    exit 1
fi
REALPATH="realpath --version"
if ! test_command $REALPATH;
then
    echo "realpath binary not installed. Please install it before running this script."
    exit 1
fi
#____________END OF CHECKS

#CONFIGURING KUBECTL
aws eks update-kubeconfig --name $CLUSTER --region $REGION

#REMOVING PREVIOUS GMSA IF NEEDED
if gmsa_already_installed;
then
    deleting_existing_gmsa
    while gmsa_already_installed
    do
        echo 'Waiting for the deletion of previous namespace'
        sleep 1
    done
fi

#____________CREATING ECR REPOSITORY
ECR_URL=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
REPOSITORY_NAME=certmanager-ca-controller
DOCKER_PREFIX=$ECR_URL/certmanager-ca-

REPOSITORY_EXISTS=$(aws ecr describe-images --repository-name $REPOSITORY_NAME --region $REGION)

if [[ ! $REPOSITORY_EXISTS ]]
then
    REPOSITORY_CREATION=$(aws ecr create-repository --repository-name $REPOSITORY_NAME --region $REGION)
else
    echo "Repository already created"
fi
#____________END OF REPOSITORY CREATION

#____________INITIATING BUILD AND INSTALLATION OF CA
echo "Starting CA installation"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL

if [[ -d "signer-ca" ]]
then
    rm -rf signer-ca
    git clone https://github.com/cert-manager/signer-ca.git
else
    git clone https://github.com/cert-manager/signer-ca.git
fi
cd signer-ca

sed -i.back 's/docker build . -t \${DOCKER_IMAGE}/docker build . -t \${DOCKER_IMAGE} --network=host/g' Makefile
sed -i.back "s/RUN go mod download/RUN export GOPROXY='direct' \&\& go mod download/g" Dockerfile

echo '        - "--signer-name='$SIGNER_NAME'"' >> config/default/manager_auth_proxy_patch.yaml
echo '        - "--certificate-duration=87600h0m0s"' >> config/default/manager_auth_proxy_patch.yaml

sed -i.back "s/  - example.com\/foo/  - ${ESCAPED_SIGNER_NAME}/g" config/e2e/rbac.yaml

#CHECKING IF SOLUTION IS INSTALLED, DELETING FIRST IF IT'S
if signer_already_installed;
then
    echo 'uninstall: ${E2E_CA}' >> Makefile
    echo '	cd config/e2e && kustomize edit set image controller=${DOCKER_IMAGE}' >> Makefile
    echo '	kustomize build config/e2e | kubectl delete -f -' >> Makefile
    echo 'Uninstalling existing version of signer-ca'
    make uninstall
    #WAITING FOR NAMESPACE DELETION TO COMPLETE
    while signer_already_installed
    do
        echo 'Waiting for the deletion of the previous namespace'
        sleep 1
    done
fi
make docker-build docker-push deploy-e2e DOCKER_PREFIX=$DOCKER_PREFIX

cd ..

#____________END OF CA BUILD AND INSTALLATION

#____________CONFIGURATION OF gMSA INSTALLATION SCRIPT TO USE ISNTALLED CA
echo "Starting gMSA installation"
if [[ -d "windows-gmsa" ]]
then
    echo "Removing existing folder"
    rm -rf windows-gmsa
    git clone https://github.com/kubernetes-sigs/windows-gmsa.git
else
    git clone https://github.com/kubernetes-sigs/windows-gmsa.git
fi

cd windows-gmsa/admission-webhook/deploy

#CHANGE THE SIGNER NAME FOR THE ONE WE CONFIGURED PREVIOUSLY IN THE CA
sed -i.back "s/signerName: kubernetes.io\/kubelet-serving/signerName: $ESCAPED_SIGNER_NAME/g" create-signed-cert.sh

#GETTING THE CREATED CA CERTIFICATE AND UPDATING IT IN THE DEPLOYMENT FILE
SECRET=$(kubectl get secrets --sort-by {.metadata.creationTimestamp} -n signer-ca-system | grep signer-ca | tail -1 | awk '{print $1}')
CA=$(kubectl get secrets $SECRET -o jsonpath='{.data.tls\.crt}' -n signer-ca-system)
sed -i.back "s/.*CA_BUNDLE=.*/        CA_BUNDLE=$CA \\\/g" deploy-gmsa-webhook.sh

#FIXING FILE FOR MACOS USERS
MACOS=$(sw_vers)
if [[ $MACOS ]]
then
    sed -i.back2 "s/-w 0/-b 0/g" deploy-gmsa-webhook.sh
    sed -i.back2 "s/-w 0/-b 0/g" create-signed-cert.sh
fi

#RUNNING THE INSTALLATION
./deploy-gmsa-webhook.sh --file ./gmsa-manifests --image sigwindowstools/k8s-gmsa-webhook:latest --overwrite
#END OF gMSA INSTALLATION

#END OF SCRIPT