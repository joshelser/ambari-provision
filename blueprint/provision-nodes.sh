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

USAGE="Usage: provision-nodes.sh <private_key> <node> [<node> ...]"
fail() {
  echo "\n${RED}Error: ${NC}$1"
  exit 1
}

status() {
  echo "\n${GREEN}$@${NC}"
}

if [[ $# -lt 2 ]]; then
  echo $USAGE
  fail "Expected at least two arguments"
fi

# Start: Resolve Script Directory
SOURCE="${BASH_SOURCE[0]}"
while [ -h "${SOURCE}" ]; do # resolve $SOURCE until the file is no longer a symlink
   bin="$( cd -P "$( dirname "${SOURCE}" )" && pwd )"
   SOURCE="$(readlink "${SOURCE}")"
   [[ "${SOURCE}" != /* ]] && SOURCE="${bin}/${SOURCE}" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
bin="$( cd -P "$( dirname "${SOURCE}" )" && pwd )"
script=$( basename "${SOURCE}" )
# Stop: Resolve Script Directory

pk=$1
shift

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $pk "
SCP="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $pk "

first_node=""
last_node=""
for node in $@; do
  if [[ $first_node == "" ]]; then
    first_node=$node
  fi
  last_node=node
  #ambari_repo_cmd="wget -O /etc/yum.repos.d/ambari.repo http://s3.amazonaws.com/dev.hortonworks.com/ambari/centos6/2.x/latest/2.1.0/ambaribn.repo"
  ambari_repo_cmd="wget -O /etc/yum.repos.d/ambari.repo http://dev.hortonworks.com.s3.amazonaws.com/ambari/centos6/2.x/latest/2.1.3.0/ambaribn.repo"
  
  status "Provisioning $node"
  $SSH $node $ambari_repo_cmd || fail "Failed to fetch Ambari repo file"
  
  status "Installing packages"
  $SSH $node "yum install -y pssh vim git tmux gcc-c++ sysstat ambari-agent" || fail "Failed to install packages"
  
  $SCP "$pk" $node:~/.ssh/id_rsa || fail "Failed to copy private key"

  status "Creating test user"
  retcode=$($SSH $node 'useradd -m hrt_qa; echo $?')
  if [[ $retcode == "0" ]]; then
    # Created the user
    echo "Created user hrt_qa"
  elif [[ $retcode == "9" ]]; then
    # User already exists, continue on
    echo "User hrt_qa already exists, continuing"
  else
    fail "Failed to create hrt_qa"
  fi

  $SSH $node gpasswd -a hrt_qa wheel || fail "Failed to add hrt_qa to wheel"
  $SSH $node "echo '%wheel  ALL=(ALL)       NOPASSWD: ALL' > /etc/sudoers.d/hrt_qa" || fail "Failed to configure sudoers for hrt_qa"

  $SSH $node mkdir -p /home/hrt_qa/.ssh || fail "Failed to create hrt_qa's SSH directory"
  $SCP "$pk" $node:/home/hrt_qa/.ssh/id_rsa || fail "Failed to copy private key"
  $SSH $node chown -R hrt_qa: /home/hrt_qa || fail "Failed to change ownership of hrt_qa's home directory"

  if [[ -f ~/.tmux.conf ]]; then 
    $SCP ~/.tmux.conf $node: || fail "Failed to copy .tmux.conf"
  fi

  status 'Configuring Git'
  gitconfig = <<EOF
  [credential]
    helper = cache
  EOF
  $SSH $h "echo '$gitconfig' >> /root/.gitconfig" || fail 'Failed to configure Git'
  $SSH $h "echo '$gitconfig' >> /home/hrt_qa/.gitconfig" || fail 'Failed to configure Git'

  status "Configuring and starting ambari agent"
  $SSH $node sed "s/hostname=localhost/hostname=$first_node/" /etc/ambari-agent/conf/ambari-agent.ini -i
  $SSH $node ambari-agent start
done

if [[ $first_node == "" ]]; then
  fail "Unexpected logic error. Should have a first node."
fi

if [[ $last_node == "" ]]; then
  fail "Unexpected logic error. Should have a last node."
fi

# TODO check response code in curl output

status "Loading blueprint"
curl --user admin:admin -H 'X-Requested-By: ambari' -X POST http://$first_node:8080/api/v1/blueprints/hadoop -d @${bin}/3-node-hbase/blueprint.json || fail "Failed to put blueprint."

status "Loading cluster"
curl --user admin:admin -H 'X-Requested-By: ambari' -X POST http://$first_node:8080/api/v1/clusters/hadoop -d @${bin}/3-node-hbase/cluster.json || fail "Failed to put cluster."

status "Done!"
