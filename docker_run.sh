#!/bin/bash
# Copyright 2022 Xilinx Inc.

confirm() {
  echo -en "\n\nDo you agree to the terms and wish to proceed [y/n]? "
  read REPLY
  case $REPLY in
  [Yy]) ;;
  [Nn]) exit 0 ;;
  *) confirm ;;
  esac
  REPLY=''
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage: $0 <image>"
  exit 2
fi

if [ -z "$1" ]; then
  echo "Usage: $0 <Vitis_AI_DOCKER_NAME>"
  exit 2
fi

if [ -z "$1" ]; then
  echo "Usage: $0 <Vitis_AI_DOCKER_NAME>"
  exit 2
fi

HERE=$(pwd -P) # Absolute path of current directory
if [[ -z $ROOTLESS ]]; then
  # running in rootful mode - use user's UID and GID inside the container
  user=$(whoami)
  uid=$(id -u)
  gid=$(id -g)
else
  # running in rootless mode - use root inside the container
  user=root
  uid=0
  gid=0
fi

DOCKER_REPO="xilinx/"

BRAND=vitis-ai
VERSION=latest

CPU_IMAGE_TAG=${DOCKER_REPO}${BRAND}-cpu:${VERSION}
GPU_IMAGE_TAG=${DOCKER_REPO}${BRAND}-gpu:${VERSION}
IMAGE_NAME="$1"
DEFAULT_COMMAND="bash"

if [[ $# -gt 0 ]]; then
  shift 1
  DEFAULT_COMMAND="$@"
  if [[ -z "$1" ]]; then
    DEFAULT_COMMAND="bash"
  fi
fi

DETACHED="-it"

# Below we ignore errors when find tries to traverse subfolders of /dev
# that non-privileged users do not have access to
xclmgmt_driver="$(find /dev -name xclmgmt\* 2>/dev/null)"
podman_devices=""
for i in ${xclmgmt_driver}; do
  podman_devices+="--device=$i "
done

render_driver="$(find /dev/dri -name renderD\* /dev/null)"
for i in ${render_driver}; do
  podman_devices+="--device=$i "
done

kfd_driver="$(find /dev -name kfd\* 2>/dev/null)"
for i in ${kfd_driver}; do
  podman_devices+="--device=$i "
done

DOCKER_RUN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ "$HERE" != "$DOCKER_RUN_DIR" ]; then
  echo "WARNING: Please start 'podman_run.sh' from the Vitis-AI/ source directory"
fi

MOUNTS="
    -v $DOCKER_RUN_DIR:/vitis_ai_home
    -v $HERE:/workspace
    -v /dev/shm:/dev/shm
"

# Mount the Xilinx DSA if installed
if [[ -d /opt/xilinx ]]; then
  MOUNTS+="
    -v /opt/xilinx/dsa:/opt/xilinx/dsa
    -v /opt/xilinx/overlaybins:/opt/xilinx/overlaybins
"
fi

podman_run_params=$(
  cat <<-END
    --security-opt=label=disable \
    -e ROOTLESS \
    -e USER=$user -e UID=$uid -e GID=$gid \
    -v /scratch/kiw94553/fpga/Vitis-AI/fixed_bashrc:/etc/bash.bashrc \
    -v /home/kiw94553/.ssh:/root/.ssh
    -w /workspace \
    --rm \
    --network=host \
    $MOUNTS \
    ${DETACHED} \
    ${RUN_MODE} \
    $IMAGE_NAME \
    $DEFAULT_COMMAND
END
)

echo "Docker RUN command args: $podman_run_params"

##############################

if [[ ! -f ".confirm" ]]; then

  if [[ $IMAGE_NAME == *"gpu"* ]]; then
    arch="gpu"
  elif [[ $IMAGE_NAME == *"rocm"* ]]; then
    arch='rocm'
  else
    arch='cpu'
  fi

  prompt_file="./podman/podmanfiles/PROMPT/PROMPT_${arch}.txt"

  sed -n '1, 5p' $prompt_file
  read -n 1 -s -r -p "Press any key to continue..." key

  sed -n '5, 15p' $prompt_file
  read -n 1 -s -r -p "Press any key to continue..." key

  sed -n '15, 28p' $prompt_file
  read -n 1 -s -r -p "Press any key to continue..." key

  sed -n '28, 61p' $prompt_file
  read -n 1 -s -r -p "Press any key to continue..." key

  sed -n '62, 224p' $prompt_file
  read -n 1 -s -r -p "Press any key to continue..." key

  sed -n '224, 308p' $prompt_file
  read -n 1 -s -r -p "Press any key to continue..." key

  sed -n '309, 520p' $prompt_file
  read -n 1 -s -r -p "Press any key to continue..." key

  confirm
fi

touch .confirm
podman pull $IMAGE_NAME
if [[ $IMAGE_NAME == *"gpu"* ]]; then
  podman run \
    $podman_devices \
    --gpus all \
    $podman_run_params
elif [[ $IMAGE_NAME == *"rocm"* ]]; then
  podman run \
    $podman_devices \
    --group-add=render --group-add video --ipc=host --cap-add=SYS_PTRACE --security-opt seccomp=unconfined \
    $podman_run_params
else
  podman run \
    $podman_devices \
    $podman_run_params
fi
