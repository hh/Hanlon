#!/bin/bash
HANLON_SOURCE_PATH="$(git rev-parse --show-toplevel)"
HANLON_STATIC_PATH="/opt/hanlon/static"
HANLON_IMAGE_PATH="/opt/hanlon/image"
HANLON_DATA_PATH="/opt/hanlon/data/db"
DOCKER_HOST=$(ip addr show dev $(ip route list 0/0 | awk '{print $5}') | awk '/inet / {gsub(/\/.*$/, "", $2); print $2}')
HANLON_SUBNETS="$(ip route list | grep $DOCKER_HOST | awk '{print $1}'),172.17.0.0/16"
unset http_proxy

if [[ $# -eq 0 ]] ; then
  echo "Script options are [start|stop|restart]."
  echo
  echo "  start   - Starts all Hanlon containers, stopping/removing if they exist"
  echo "  stop    - Stops/removes all Hanlon containers"
  echo "  restart - Restarts only hanlon-server container, to reload source"
  echo "  pull    - Update docker images from online repositories"
  echo
  exit 0
fi

if [[ "$1" == "stop" ]] || [[ "$1" == "start"  ]] ; then
  HANLON_CONTAINERS=`sudo docker ps -a -q --filter="name=hanlon-"`
  if [[ ${#HANLON_CONTAINERS} > 0 ]] ; then
    echo "Stopping Hanlon Docker containers"
    sudo docker stop $HANLON_CONTAINERS
    echo "Removing Hanlon Docker containers"
    sudo docker rm $HANLON_CONTAINERS
  fi
fi

if [[ "$1" == "start"  ]] ; then

  echo "Cleaning up Hanlon conf files"
  sudo rm -f $HANLON_SOURCE_PATH/web/config/hanlon_server.conf
  sudo rm -f $HANLON_SOURCE_PATH/cli/config/hanlon_client.conf

  echo "Starting Hanlon Docker containers"
  sudo docker run -d -v $HANLON_DATA_PATH:/data/db --name hanlon-mongodb dockerfile/mongodb mongod --smallfiles
  sudo docker run -d --privileged -p 8026:8026 \
                  -e DOCKER_HOST=$DOCKER_HOST \
                  -e HANLON_SUBNETS=$HANLON_SUBNETS \
                  -e HANLON_STATIC_PATH=$HANLON_STATIC_PATH \
                  -v $HANLON_IMAGE_PATH:/home/hanlon/image \
                  -v $HANLON_SOURCE_PATH:/home/hanlon \
                  --name hanlon-server --link hanlon-mongodb:mongo cscdock/hanlon

  while true; do
    echo "Waiting for Hanlon Server container to start"
    curl -I http://127.0.0.1:8026/hanlon/api/v1/config/ipxe
    rc=$?
    if [[ $rc == 0 ]] ; then
      sudo docker run -d -e DOCKER_HOST=$DOCKER_HOST -p 69:69/udp --name hanlon-atftpd --link hanlon-server:hanlon cscdock/atftpd
      exit 0
    fi
  sleep 5
  done

fi

if [[ "$1" == "restart"  ]] ; then
  HANLON_CONTAINERS=`sudo docker ps -a -q --filter="name=hanlon-server"`
  if [[ ${#HANLON_CONTAINERS} > 0 ]] ; then
    echo "Stopping Hanlon Server container"
    sudo docker stop $HANLON_CONTAINERS
    echo "Removing Hanlon Server container"
    sudo docker rm $HANLON_CONTAINERS
  fi

  echo "Cleaning up Hanlon conf files"
  sudo rm -f $HANLON_SOURCE_PATH/web/config/hanlon_server.conf
  sudo rm -f $HANLON_SOURCE_PATH/cli/config/hanlon_client.conf

  sudo docker run -d --privileged -p 8026:8026 \
                  -e DOCKER_HOST=$DOCKER_HOST \
                  -e HANLON_SUBNETS=$HANLON_SUBNETS \
                  -e HANLON_STATIC_PATH=$HANLON_STATIC_PATH \
                  -v $HANLON_IMAGE_PATH:/home/hanlon/image \
                  -v $HANLON_SOURCE_PATH:/home/hanlon \
                  --name hanlon-server --link hanlon-mongodb:mongo cscdock/hanlon

fi

if [[ "$1" == "pull" ]] ; then
  sudo docker pull cscdock/hanlon
  sudo docker pull cscdock/hanlon-client
  sudo docker pull cscdock/atftpd
  sudo docker pull dockerfile/mongodb
fi