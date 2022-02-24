# Amazon EKS - gMSA Webhook Autoinstall

Currently, Amazon EKS does not support "kubernetes.io/kubelet-serving" certificates for non-node objects. As a result the gMSA [scripts](https://github.com/kubernetes-sigs/windows-gmsa/blob/master/admission-webhook/deploy/create-signed-cert.sh#L120_) for gMSA admission-webhook version 0.2.0 and 0.3.0 installation are not compatible for deployment in Amazon EKS.

Thinking on an alternative, we developed a workaround which has two major objectives:

1. Install [certmanager-CA](https://github.com/cert-manager/signer-ca);
2. Use it to sign the CSRs for gMSA instead of the default controller.

## Script workflow

This script is going to perform the following activities:

1. Check all software dependencies and install them (supported only on Amazon Linux 2 hosts)
2. Create (if not, yet, created) the 'certmanager-ca-controller' repository in ECR in the specified region
3. Uninstall (if any) previous installation of gMSA
4. Uninstall (if any) previous installation of signer-ca
5. Install the cert-manager [signer-ca](https://github.com/cert-manager/signer-ca) (master branch)
6. Install gMSA [v0.3.0](https://github.com/kubernetes-sigs/windows-gmsa/releases/tag/v0.3.0)

## Prerequisites

**IAM**
This script requires, at least, the following actions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "ecr:CreateRepository",
                "ecr:DescribeImages",
                "ecr:GetAuthorizationToken",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload"
            ],
            "Resource": [
                "arn:aws:ecr:*:*:repository/certmanager-ca-controller"
            ]
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "arn:aws:eks:*:765427072911:cluster/*"
        },
        {
            "Sid": "VisualEditor3",
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```
The recommended approach is to run this script from an EC2 instance and configure this [instance's profile](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2_instance-profiles.html) to use the above mentioned policy.

You'd also need to add this instance profile to the EKS [aws-auth](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html) ConfigMap so that the script could run 'kubectl' commands. To perform this mapping, the following command could be used:

```shell
$  eksctl create iamidentitymapping \
  --username admin \
  --cluster  <cluster-name> \
  --arn arn:aws:iam::<account>:role/<role-used-for-instance-profile> \
  --group system:masters
```

**For security purposes, this mapping can be removed after the successful installation.**

*You can also use the AWS CLI commands and policies available in the Example folder to set up the EC2 Instance Profile and add as part of the EKS aws-auth ConfigMap.*

**Softwares**

It's necessary that the following binaries are installed in the host that is running this script:

1. docker
2. cfssl
3. cfssljson
4. kustomize
5. git
6. kubectl
7. realpath

Additionally, Docker daemon should be running so that the script could successfully build the signer-ca image.

**If you are using Amazon Linux 2 as the OS of the EC2 instance you're executing the script, you have the option to inform the "AL2" parameter which would trigger the automatic installation/configuration of the host.**

### Installing the gMSA admission-webhook 

The main component of this script is the "installation.sh" file. It receives five positional arguments:

1. The account of the EKS cluster in which the installation is being performed.
2. The region of the EKS cluster in which the installation is being performed.
3. The name of the EKS cluster  in which the installation is being performed.
4. The name of the signer to be deployed. This name will be used in the **signerName** property of the CertificateSigningRequests [object](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.23/#certificatesigningrequestspec-v1-certificates-k8s-io).
5. automatic software dependencies installation/configuration. By default, this value is set to "AL2" which enables the automatic feature. 

The following commands could be used to run the deploy script from an EC2 instance:

```
$ sudo -i 
$ yum install -y git
$ git clone https://github.com/aws-samples/amazon-eks-gmsa-admission-webhook-autoinstall
$ cd amazon-eks-gmsa-admission-webhook-autoinstall/
$ bash installation.sh <account-id> <region-id> <eks-cluster-name> my-private-signer.com/my-signer AL2
```

Kindly note that <my-private-signer.com/my-signer> is the parameter for the name of the signer to be used in the CSR and could be any value in the "domain.com/name" format.
