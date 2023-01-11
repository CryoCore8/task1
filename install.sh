#!/bin/bash
#Script to install dependencies and provision HA k3s AWX with 3 nodes.

#Get variables
NAMESPACE="awx"
read -p "Which version of AWX would you like to install (example: 0.25.0 | https://github.com/ansible/awx-operator/tags): " TAG
echo ""
read -p "What is the internal hostname you'd like the instance to have (example: awx.intra.net): " HOSTNAME
echo ""
echo -e "Updating & upgrading system and installing dependencies\n"

#Update system & install dependencies

#Check if Docker keyring exists
if [ ! -f /etc/apt/trusted.gpg ]; then
        echo "Adding docker keyring in /etc/apt/trusted.gpg"
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        echo ""
fi

#Check if Docker repository is listed
cat /etc/apt/sources.list | grep -i "download.docker.com" >/dev/null
if [ "$?" -eq "1" ]; then
        echo "Adding docker repository"
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
        echo ""
fi

#Check if Docker is installed
which docker >/dev/null
if [ "$?" -eq "1" ]; then
        echo "Installing docker"
        apt install docker-ce
fi

#Check if Projects directory exists for k3s PV
if [ ! -d "/data/projects" ]; then
        echo "Creating projects directory"
        mkdir -p /data/projects
fi

#Check if Postgres directory exists for k3s PV
if [ ! -d "/data/postgres" ]; then
        echo "Creating postgres directory"
        mkdir -p /data/postgres
fi

#Ensure correct permissions and ownership
chmod 755 /data/postgres
chown 1000:0 /data/projects

#Check if k3s is installed
which k3s >/dev/null
if [ "$?" -eq "1" ]; then
    echo -e "Installing k3s\n\n"
    curl -sfL https://get.k3s.io | sh -
fi

#Check if Kustomize is installed
which kustomize >/dev/null
if [ "$?" -eq "1" ]; then
    echo -e "Installing Kustomize\n\n"
    cd /usr/local/sbin/ && curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash
    echo ""
fi

#Deploy the project
echo -e "Deploying HA AWX. This can take some time.\n\n"

#navigate to project directory
cd $(pwd)

#Check if namespace exists
kubectl get namespace | grep awx >/dev/null
if [ "$?" -eq "1" ]; then
        kubectl create namespace $NAMESPACE
        echo ""
fi

#Switch context to awx namespace to shorten the kubectl commands
kubectl config set-context --namespace=$NAMESPACE --current

#Set desired hostname to config file
sed -i 's/$HOSTNAME/'$HOSTNAME'/' awx.yml

#Set desired AWX operator version in config file
sed -i 's/$TAG/'$TAG'/' kustomization.yml

#Deploy the AWX Operator (due to occasional one-offs, added a line to repeat the command as that fixes it)
kustomize build . | kubectl apply -f -
if [ "$?" -eq "1" ]; then
        !!
fi
sleep 120

#Deploy custom AWX config
kubectl apply -f secret.yml
sleep 20
kubectl apply -f pv.yml
sleep 20
kubectl apply -f pvc.yml
sleep 20
kubectl apply -f awx.yml
sleep 20

echo -e "Please allow up to 5 minutes for the cluster to pull and create all images. Make sure to add the internal domain in our DNS config. You can then visi
t $HOSTNAME and log in with username \"admin\" and password supplied in secret.yml file."
