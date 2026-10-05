#!/bin/bash

# Build HST images with the daemon started by the Ubuntu DinD executor image.
# Run this in a privileged container created from the completed executor image.

set -euo pipefail

export DOT_GITHUB_DOCKER_SCRIPTS=${DOT_GITHUB_DOCKER_SCRIPTS:-"$(dirname "${BASH_SOURCE[0]}")"}
. "$DOT_GITHUB_DOCKER_SCRIPTS/lib_vpp.sh"

if [ "$OS_ID" != "ubuntu" ]; then
    echo "HST images are supported only on Ubuntu."
    exit 1
fi

docker info >/dev/null

bundle_dir=${HST_BUNDLE_DIR:-/tmp/hst-bundle}
mkdir -p "$bundle_dir/cache-mounts"
cd "$DOCKER_VPP_DIR"

bake_branches=${HST_BAKE_BRANCHES:-${VPP_BRANCHES[$OS_NAME]}}
for branch in $bake_branches; do
    if [[ " ${VPP_BRANCHES[$OS_NAME]} " != *" $branch "* ]]; then
        echo "Unsupported HST bake branch for $OS_NAME: $branch" >&2
        exit 2
    fi

    branch_tag=${branch//\//-}
    git checkout -q "$branch"
    expect_cache_mounts=false
    if grep -Fq -- '--mount=type=cache' test/hs-test/docker/Dockerfile.ginkgo; then
        expect_cache_mounts=true
    fi

    # stable/2606 uses :latest. Newer branches pass RUN_ID to build_hst.sh.
    image_tag=latest
    # shellcheck disable=SC2016
    if grep -Fq 'IMAGE_TAG=$(RUN_ID)' test/hs-test/Makefile; then
        image_tag=$branch_tag
    fi

    # The executor installs dependencies oldest-to-newest and retains master's
    # package. Switch to this branch's cached package before compiling VPP.
    # shellcheck disable=SC2016
    ext_deps_deb=$(make --no-print-directory -s -C build/external \
        --eval='hst-ext-deps-package:;@echo $(DEV_DEB)' hst-ext-deps-package)
    ext_deps_package="$DOCKER_DOWNLOADS_DIR/$ext_deps_deb"
    if [ ! -f "$ext_deps_package" ]; then
        echo "ERROR: Missing cached external dependencies for $branch: $ext_deps_package" >&2
        exit 1
    fi
    echo "Installing cached external dependencies for $branch: $ext_deps_deb"
    dpkg -i "$ext_deps_package"

    echo "Building HST images for $branch (tag $image_tag)"
    make -C test/hs-test build FORCE_BUILD=true RUN_ID="$branch_tag"

    images=(
        "localhost:5001/vpp-test-base:$image_tag"
        "hs-test/vpp:$image_tag"
        "hs-test/nginx-ldp:$image_tag"
        "hs-test/nginx-server:$image_tag"
        "hs-test/h2load:$image_tag"
        "hs-test/curl:$image_tag"
        "hs-test/ab:$image_tag"
        "hs-test/wrk:$image_tag"
        "hs-test/ginkgo:$image_tag"
        "hs-test/nginx-http3:$image_tag"
        "hs-test/envoy:$image_tag"
    )
    : > "$bundle_dir/$branch_tag.images"
    for image in "${images[@]}"; do
        image_id=$(docker image inspect --format '{{.Id}}' "$image")
        printf '%s %s\n' "$image" "$image_id" >> "$bundle_dir/$branch_tag.images"
    done

    docker save "${images[@]}" | gzip -1 > "$bundle_dir/$branch_tag.tar.gz"

    # Snapshot immediately after this branch's build. Workflows select this
    # directory rather than restoring the final bake's shared cache snapshot.
    if [ "$expect_cache_mounts" = true ]; then
        branch_cache_dir="$bundle_dir/cache-mounts/$branch_tag"
        bash "$DOT_GITHUB_DOCKER_SCRIPTS/hst_cache.sh" export "$branch_cache_dir"

        for cache in hst_builder/apt hst_builder/apt-lists hst_builder/downloads \
            default/downloads default/go-mod; do
            if [ -z "$(find "$branch_cache_dir/$cache" -type f -size +0c -print -quit)" ]; then
                echo "ERROR: Empty HST cache snapshot for $branch: $cache" >&2
                exit 1
            fi
        done
        for download in 'go*.tar.gz' 'docker-ce-cli*.deb'; do
            if [ -z "$(find "$branch_cache_dir/default/downloads" \
                -type f -name "$download" -size +0c -print -quit)" ]; then
                echo "ERROR: Missing HST cached download for $branch: $download" >&2
                exit 1
            fi
        done
    fi

    git restore .
    git clean -qfdx
done

# HST uses a local registry and a containerized BuildKit builder. Keep their
# images available in a fresh executor daemon without pulling them again.
save_runtime_image() {
    local name=$1
    local image=$2
    local image_id
    image_id=$(docker image inspect --format '{{.Id}}' "$image")
    printf '%s %s\n' "$image" "$image_id" > "$bundle_dir/$name.images"
    docker save "$image" | gzip -1 > "$bundle_dir/$name.tar.gz"
}

save_runtime_image hst-runtime-registry registry:2
buildkit_container=$(docker ps -a --filter name='^/buildx_buildkit_hst_builder0$' \
    --format '{{.ID}}' | head -n 1)
if [ -n "$buildkit_container" ]; then
    buildkit_image=$(docker inspect --format '{{.Config.Image}}' "$buildkit_container")
    save_runtime_image hst-runtime-buildkit "$buildkit_image"
fi
