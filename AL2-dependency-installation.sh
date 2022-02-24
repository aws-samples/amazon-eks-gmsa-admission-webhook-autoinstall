#!/bin/bash

# set -x
test_command(){

    $@ > /dev/null 2>&1
    if [ $? == '127' ]
    then
        echo "Command $1 not installed"
        return 1
    else
        echo "Command $1 installed"
        return 0
    fi
}

install_aws_cli() {
    echo "Installing AWS CLI"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
}
install_docker() {
    echo "Installing Docker"
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo yum install docker -y
    sudo service docker start
    sudo systemctl enable docker
    sudo usermod -a -G docker ec2-user
}
install_cfssl() {
    echo "Installing CFSSL"
    VERSION=$(curl --silent "https://api.github.com/repos/cloudflare/cfssl/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    VNUMBER=${VERSION#"v"}
    wget https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssl_${VNUMBER}_linux_amd64 -O cfssl
    chmod +x cfssl
    sudo mv cfssl /usr/local/sbin
}
install_cfssljson() {
    echo "Installing CFSSLJSON"
    VERSION=$(curl --silent "https://api.github.com/repos/cloudflare/cfssl/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    VNUMBER=${VERSION#"v"}
    wget https://github.com/cloudflare/cfssl/releases/download/${VERSION}/cfssljson_${VNUMBER}_linux_amd64 -O cfssljson
    chmod +x cfssljson
    sudo mv cfssljson /usr/local/sbin
}
install_kustomize() {
    echo "Installing Kustomize"
    curl --silent --location --remote-name \
    "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v3.2.3/kustomize_kustomize.v3.2.3_linux_amd64" && \
    chmod a+x kustomize_kustomize.v3.2.3_linux_amd64 && \
    sudo mv kustomize_kustomize.v3.2.3_linux_amd64 /usr/local/sbin/kustomize
}
install_git() {
    echo "Installing Git"
    sudo yum install -y git
}
install_kubectl() {
    echo "Installing Kubectl"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo chmod +x kubectl
    sudo install kubectl /usr/local/sbin

}
install_realpath() {
    echo "Installing realpath"
    sudo yum install -y coreutils
}

#PERFORMING CHECKS
AWS_CLI="aws --version"
if  ! test_command $AWS_CLI;
then
    echo "AWS binary not installed. Installing it."
    install_aws_cli
fi
DOCKER="docker version"
if ! test_command $DOCKER;
then
    echo "Docker binary not installed. Installing it."
    install_docker
fi
CFSSL="cfssl version"
if ! test_command $CFSSL;
then
    echo "cfssl binary not installed. Installing it."
    install_cfssl
fi
CFSSLJSON="cfssljson -version"
if ! test_command $CFSSLJSON;
then
    echo "cfssljson binary not installed. Installing it."
    install_cfssljson
fi
KUSTOMIZE="kustomize version"
if ! test_command $KUSTOMIZE;
then
    echo "kustomize binary not installed. Installing it."
    install_kustomize
fi
GIT="git version"
if ! test_command $GIT;
then
    echo "git binary not installed. Installing it."
    install_git
fi
KUBECTL="kubectl version"
if ! test_command $KUBECTL;
then
    echo "kubectl binary not installed. Installing it."
    install_kubectl
fi
REALPATH="realpath --version"
if ! test_command $REALPATH;
then
    echo "realpath binary not installed. Installing it."
    install_realpath
fi