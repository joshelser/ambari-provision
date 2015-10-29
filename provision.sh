#!/bin/sh

BLACK="\033[0;30m"
DARK_GRAY="\033[1;30m"
RED="\033[0;31m"
LIGHT_RED="\033[1;31m"
GREEN="\033[0;32m"
LIGHT_GREEN="\033[1;32m"
BROWN="\033[33m"
YELLOW="\033[1;33m"
BLUE="\033[ 0;34m"
LIGHT_BLUE="\033[1;34m"
PURPLE="\033[0;35m"
LIGHT_PURPLE="\033[;35m"
CYAN="\033[0;36m"
LIGHT_CYAN="\033[ 1;36m"
LIGHT_GRAY="\033[0;37m"
WHITE="\033[1;37m"
NC="\033[0m"

USAGE="Usage: provision.sh <hostname> <private_key>"
fail() {
  echo "${RED}Error: ${NC}$1"
  exit 1
}

status() {
  echo "${GREEN}$1${NC}"
}

if [[ $# -ne 2 ]]; then
  echo "${YELLOW}$USAGE"
  fail "Expected two arguments"
fi

# the host
h=$1
shift

pk=$1
shift

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $pk "
SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $pk "

#ambari_repo_cmd="wget -O /etc/yum.repos.d/ambari.repo http://s3.amazonaws.com/dev.hortonworks.com/ambari/centos6/2.x/latest/2.1.0/ambaribn.repo"
ambari_repo_cmd="wget -O /etc/yum.repos.d/ambari.repo http://dev.hortonworks.com.s3.amazonaws.com/ambari/centos6/2.x/latest/2.1.3.0/ambaribn.repo"

$SSH $h $ambari_repo_cmd || fail "Failed to fetch Ambari repo file"

status "Installing packages"
$SSH $h "yum install -y pssh vim git tmux ambari-server gcc-c++ sysstat" || fail "Failed to install packages"

status "Running Ambari Server setup"
$SSH $h "ambari-server setup -s" || fail "Failed to setup ambari-server"
$SSH $h "ambari-server start" || fail "Failed to start ambari-server"

$SCP "$pk" $h:~/.ssh/id_rsa || fail "Failed to copy private key"

status "Creating test user"
$SSH $h useradd -m hrt_qa || fail "Failed to create hrt_qa"
$SSH $h gpasswd -a hrt_qa wheel || fail "Failed to add hrt_qa to wheel"
$SSH $h "echo '%wheel  ALL=(ALL)       NOPASSWD: ALL' > /etc/sudoers.d/hrt_qa" || fail "Failed to configure sudoers for hrt_qa"

if [[ -f ~/.tmux.conf ]]; then 
  $SCP ~/.tmux.conf $h: || fail "Failed to copy .tmux.conf"
fi

status "Installing system test packages"
$SSH $h "easy_install pytest" || fail "Failed to install pytest"
