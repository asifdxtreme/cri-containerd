#!/bin/bash

# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -o nounset
set -o pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..
. ${ROOT}/hack/versions

# FOCUS focuses the test to run.
FOCUS=${FOCUS:-}
# SKIP skips the test to skip.
SKIP=${SKIP:-"attach|portforward|RunAsUser|host port"}
REPORT_DIR=${REPORT_DIR:-"/tmp"}

if [[ -z "${GOPATH}" ]]; then
  echo "GOPATH is not set"
  exit 1
fi

if [[ ! "${PATH}" =~ (^|:)${GOPATH}/bin(|/)(:|$) ]]; then
  echo "GOPATH/bin is not in path"
  exit 1
fi

if [ ! -x ${ROOT}/_output/cri-containerd ]; then
  echo "cri-containerd is not built"
  exit 1
fi

CRITEST=critest
CRITEST_PKG=github.com/kubernetes-incubator/cri-tools
CRICONTAINERD_SOCK=/var/run/cri-containerd.sock

# Install critest
if [ ! -x "$(command -v ${CRITEST})" ]; then
  go get -d ${CRITEST_PKG}/...
  cd ${GOPATH}/src/${CRITEST_PKG}
  git fetch --all
  git checkout ${CRITEST_VERSION}
  make
fi
which ${CRITEST}

# Start containerd
if [ ! -x "$(command -v containerd)" ]; then
  echo "containerd is not installed, please run hack/install-deps.sh"
  exit 1
fi
sudo pkill containerd
sudo containerd -l debug &> ${REPORT_DIR}/containerd.log &

# Wait for containerd to be running by using the containerd client ctr to check the version
# of the containerd server. Wait an increasing amount of time after each of five attempts
MAX_ATTEMPTS=5
attempt_num=1
until sudo ctr version &> /dev/null || (( attempt_num == MAX_ATTEMPTS ))
do
    echo "Attempt $attempt_num to connect to containerd failed! Trying again in $attempt_num seconds..."
    sleep $(( attempt_num++ ))
done

# Start cri-containerd
cd ${ROOT}
sudo _output/cri-containerd --alsologtostderr --v 4 &> ${REPORT_DIR}/cri-containerd.log &

# Run cri validation test
sudo env PATH=${PATH} GOPATH=${GOPATH} ${CRITEST} --runtime-endpoint=${CRICONTAINERD_SOCK} --focus="${FOCUS}" --ginkgo-flags="--skip=\"${SKIP}\"" validation
test_exit_code=$?

sudo pkill containerd

exit ${test_exit_code}
