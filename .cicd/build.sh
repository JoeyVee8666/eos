#!/bin/bash
set -eo pipefail
. ./.cicd/helpers/general.sh

function cleanup() {
    if [[ "$(uname)" != 'Darwin' ]]; then
        echo "[Cleaning up docker container]"
        echo " - docker container kill $BUILDKITE_JOB_ID"
        docker container kill $BUILDKITE_JOB_ID || true # -v and --mount don't work quite well when it's docker in docker, so we need to use docker's cp command to move the build script in
    fi
}
trap cleanup 0

export DOCKERIZATION=false
[[ $ENABLE_INSTALL == true ]] && . ./.cicd/helpers/populate-template-and-hash.sh '<!-- BUILD' '<!-- INSTALL' || . ./.cicd/helpers/populate-template-and-hash.sh '<!-- BUILD'
if [[ "$(uname)" == 'Darwin' ]]; then
    # You can't use chained commands in execute
    if [[ $TRAVIS == true ]]; then
        ccache -s
        brew reinstall openssl@1.1 # Fixes issue where builds in Travis cannot find libcrypto.
        sed -i -e 's/^cmake /cmake -DCMAKE_CXX_COMPILER_LAUNCHER=ccache /g' /tmp/$POPULATED_FILE_NAME
    fi
    . $HELPERS_DIR/populate-template-and-hash.sh -h # obtain $FULL_TAG (and don't overwrite existing file)
    source ~/.bash_profile # Make sure node is available for ship_test
    cat /tmp/$POPULATED_FILE_NAME
    . /tmp/$POPULATED_FILE_NAME # This file is populated from the platform's build documentation code block
else # Linux
    ARGS=${ARGS:-"--rm -t -d --name $BUILDKITE_JOB_ID -v $(pwd):$MOUNTED_DIR"}
    # sed -i '1s;^;#!/bin/bash\nexport PATH=$EOSIO_INSTALL_LOCATION/bin:$PATH\n;' /tmp/$POPULATED_FILE_NAME # /build-script: line 3: cmake: command not found
    # PRE_COMMANDS: Executed pre-cmake
    [[ ! $IMAGE_TAG =~ 'unpinned' ]] && CMAKE_EXTRAS="-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
    if [[ $IMAGE_TAG == 'amazon_linux-2-pinned' ]]; then
        PRE_COMMANDS="export PATH=/usr/lib64/ccache:\\\$PATH"
    elif [[ "$IMAGE_TAG" == 'centos-7.7-pinned' ]]; then
        PRE_COMMANDS="export PATH=/usr/lib64/ccache:\\\$PATH"
    elif [[ $IMAGE_TAG == 'ubuntu-16.04-pinned' ]]; then
        PRE_COMMANDS="export PATH=/usr/lib/ccache:\\\$PATH"
    elif [[ $IMAGE_TAG == 'ubuntu-18.04-pinned' ]]; then
        PRE_COMMANDS="export PATH=/usr/lib/ccache:\\\$PATH"
    elif [[ $IMAGE_TAG == 'amazon_linux-2-unpinned' ]]; then
        PRE_COMMANDS="export PATH=/usr/lib64/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_CXX_COMPILER='clang++' -DCMAKE_C_COMPILER='clang'"
    elif [[ "$IMAGE_TAG" == 'centos-7.7-unpinned' ]]; then
        PRE_COMMANDS="source /opt/rh/devtoolset-8/enable && source /opt/rh/rh-python36/enable && export PATH=/usr/lib64/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DLLVM_DIR='/opt/rh/llvm-toolset-7.0/root/usr/lib64/cmake/llvm'"
    elif [[ $IMAGE_TAG == 'ubuntu-18.04-unpinned' ]]; then
        PRE_COMMANDS="export PATH=/usr/lib/ccache:\\\$PATH"
        CMAKE_EXTRAS="$CMAKE_EXTRAS -DCMAKE_CXX_COMPILER='clang++-7' -DCMAKE_C_COMPILER='clang-7' -DLLVM_DIR='/usr/lib/llvm-7/lib/cmake/llvm'"
    fi
    BUILD_COMMANDS="/$POPULATED_FILE_NAME"
    if [[ $TRAVIS == true ]]; then
        ARGS="$ARGS -v /usr/lib/ccache -v $HOME/.ccache:/opt/.ccache -e JOBS -e TRAVIS -e CCACHE_DIR=/opt/.ccache"
        BUILD_COMMANDS="ccache -s && $BUILD_COMMANDS"
    fi
    . $HELPERS_DIR/populate-template-and-hash.sh -h # obtain $FULL_TAG (and don't overwrite existing file)
    echo "$ docker run $ARGS $(buildkite-intrinsics) $FULL_TAG"
    eval docker run $ARGS $(buildkite-intrinsics) $FULL_TAG
    echo "$ docker cp /tmp/$POPULATED_FILE_NAME $BUILDKITE_JOB_ID:/$POPULATED_FILE_NAME"
    docker cp /tmp/$POPULATED_FILE_NAME $BUILDKITE_JOB_ID:/$POPULATED_FILE_NAME
    echo "$ docker exec $BUILDKITE_JOB_ID bash -c \"$PRE_COMMANDS \&\& $BUILD_COMMANDS\""
    eval docker exec $BUILDKITE_JOB_ID bash -c \"$PRE_COMMANDS \&\& $BUILD_COMMANDS\"
fi