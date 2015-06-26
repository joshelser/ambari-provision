#!/bin/sh

USAGE="Usage: provision.sh <hostname>"
SSH="ssh -o StrictHostKeyChecking=no,UserKnownHostsFile=/dev/null "
SCP="scp -o StrictHostKeyChecking=no,UserKnownHostsFile=/dev/null "

fail() {
  echo "Error: $1"
  exit 1
}

if [[ $# -ne 1 ]]; then
  echo "Expected one argument"
  echo $USAGE
  exit 1
fi

# the host
h=$1
shift

ambari_repo_cmd="wget -O /etc/yum.repos.d/ambari.repo http://s3.amazonaws.com/dev.hortonworks.com/ambari/centos6/2.x/latest/2.1.0/ambaribn.repo"

$SSH $h $ambari_repo_cmd || fail "Failed to fetch Ambari repo file"

echo "Installing packages"
$SSH $h "yum install -y pssh vim git tmux ambari-server" || fail "Failed to install packages"

echo "Running Ambari Server setup"
$SSH $h "ambari-server setup -s" || fail "Failed to setup ambari-server"
$SSH $h "ambari-server start" || fail "Failed to start ambari-server"

$SCP ~/.ssh/hw-dev-keypair.pem $h:~/.ssh/id_rsa || fail "Failed to copy private key"

echo "Creating test user"
$SSH $h useradd -m hrt_qa || fail "Failed to create hrt_qa"
$SSH $h gpasswd -a hrt_qa wheel || fail "Failed to add hrt_qa to wheel"
$SSH $h "echo '%wheel  ALL=(ALL)       NOPASSWD: ALL' > /etc/sudoers.d/hrt_qa" || fail "Failed to configure sudoers for hrt_qa"

$SCP ~/.tmux.conf $h: || fail "Failed to copy .tmux.conf"

echo "Installing system test packages"
$SSH $h "easy_install pytest" || fail "Failed to install pytest"
