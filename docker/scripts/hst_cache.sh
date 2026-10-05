#!/bin/bash

# Manage baked HST images and Dockerfile cache mounts for one VPP branch.
# Restore loads images first so registry and BuildKit are available locally.
# BuildKit cache mounts require explicit snapshots; docker save and --cache-to
# do not include them. Helper builds use static BusyBox without image pulls.

set -euo pipefail

load_images() {
    local bundle_dir manifest archive missing conflict image expected_id current_id
    local -a manifests
    bundle_dir=${HST_IMAGE_BUNDLE_DIR:-/opt/hst-images}
    if [ ! -d "$bundle_dir" ]; then
        return 0
    fi

    shopt -s nullglob
    manifests=("$bundle_dir"/hst-runtime-*.images)
    if [ -f "$bundle_dir/$branch_tag.images" ]; then
        manifests+=("$bundle_dir/$branch_tag.images")
    else
        echo "No baked HST images for branch $branch; HST will build them normally."
    fi
    if [ "${#manifests[@]}" -eq 0 ]; then
        return 0
    fi

    docker info >/dev/null
    for manifest in "${manifests[@]}"; do
        archive=${manifest%.images}.tar.gz
        if [ ! -f "$archive" ]; then
            echo "Missing HST image archive: $archive" >&2
            exit 1
        fi

        missing=false
        conflict=false
        while read -r image expected_id; do
            current_id=$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)
            if [ -z "$current_id" ]; then
                missing=true
            elif [ "$current_id" != "$expected_id" ]; then
                echo "Keeping existing $image ($current_id); baked image is $expected_id" >&2
                conflict=true
            fi
        done < "$manifest"

        if [ "$conflict" = true ]; then
            continue
        fi
        if [ "$missing" = true ]; then
            echo "Loading HST images from $archive"
            docker load --input "$archive"
        fi
    done
}

action=${1:-restore}
case "$action" in
    export)
        cache_dir=${2:?Usage: hst_cache.sh export CACHE_DIR}
        ;;
    restore)
        branch=${2:-master}
        if ! [[ "$branch" =~ ^[a-zA-Z0-9][a-zA-Z0-9_./-]*$ ]]; then
            echo "Invalid HST branch: $branch" >&2
            exit 2
        fi
        branch_tag=${branch//\//-}
        cache_root=${3:-/opt/hst-cache-mounts}
        cache_dir="$cache_root/$branch_tag"
        image_bundle=${HST_IMAGE_BUNDLE_DIR:-/opt/hst-images}
        if [ ! -f "$image_bundle/$branch_tag.images" ] && [ ! -d "$cache_dir" ]; then
            echo "No baked HST cache for branch $branch; HST will build images normally."
            exit 0
        fi
        echo "Restoring baked HST images and caches for $branch"
        load_images
        if [ ! -d "$cache_dir/hst_builder" ] || [ ! -d "$cache_dir/default" ]; then
            exit 0
        fi
        if [ -z "$(find "$cache_dir" -type f -print -quit)" ]; then
            echo "WARNING: HST cache snapshot is empty: $cache_dir" >&2
            exit 0
        fi
        ;;
    *)
        echo "Usage: hst_cache.sh [restore [BRANCH [CACHE_ROOT]] | export CACHE_DIR]" >&2
        exit 2
        ;;
esac

helper_dir=$(mktemp -d /tmp/hst-cache-helper.XXXXXX)
trap 'rm -rf "$helper_dir"' EXIT
cp /bin/busybox "$helper_dir/busybox"
# --no-cache also clears cache mounts. Change an ARG instead so every helper
# RUN executes while retaining the mounts used by the HST Dockerfiles.
helper_nonce=${helper_dir##*/}

case "$action" in
    export)
        mkdir -p "$cache_dir/hst_builder" "$cache_dir/default"

        cat > "$helper_dir/Dockerfile.hst_builder" <<'EOF'
FROM scratch AS snapshot
COPY busybox /bin/busybox
SHELL ["/bin/busybox", "sh", "-c"]
ARG HST_CACHE_NONCE
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/downloads \
    /bin/busybox mkdir -p /export/apt /export/apt-lists /export/downloads \
    && /bin/busybox cp -a /var/cache/apt/. /export/apt/ \
    && /bin/busybox cp -a /var/lib/apt/. /export/apt-lists/ \
    && /bin/busybox cp -a /var/cache/downloads/. /export/downloads/
FROM scratch
COPY --from=snapshot /export/ /
EOF

        cat > "$helper_dir/Dockerfile.default" <<'EOF'
FROM scratch AS snapshot
COPY busybox /bin/busybox
SHELL ["/bin/busybox", "sh", "-c"]
ARG HST_CACHE_NONCE
RUN --mount=type=cache,target=/var/cache/downloads \
    --mount=type=cache,target=/var/cache/go-mod \
    /bin/busybox mkdir -p /export/downloads /export/go-mod \
    && /bin/busybox cp -a /var/cache/downloads/. /export/downloads/ \
    && /bin/busybox cp -a /var/cache/go-mod/. /export/go-mod/
FROM scratch
COPY --from=snapshot /export/ /
EOF

        docker buildx build --builder hst_builder --network none \
            --build-arg "HST_CACHE_NONCE=$helper_nonce" \
            --output "type=local,dest=$cache_dir/hst_builder" \
            --file "$helper_dir/Dockerfile.hst_builder" "$helper_dir"
        docker buildx build --builder default --network none \
            --build-arg "HST_CACHE_NONCE=$helper_nonce" \
            --output "type=local,dest=$cache_dir/default" \
            --file "$helper_dir/Dockerfile.default" "$helper_dir"
        echo "Exported HST cache mounts:"
        du -sh "$cache_dir"/*/*
        ;;

    restore)

        # BusyBox cp -an skips an existing directory rather than merging its
        # children. Recurse into existing directories and copy missing entries.
        cat > "$helper_dir/copy-missing.sh" <<'EOF'
set -e
copy_missing() {
    local source=$1 destination=$2 entry target
    /bin/busybox mkdir -p "$destination"
    for entry in "$source"/* "$source"/.[!.]* "$source"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        target="$destination/${entry##*/}"
        if [ -d "$entry" ] && [ ! -L "$entry" ] \
            && [ -d "$target" ] && [ ! -L "$target" ]; then
            copy_missing "$entry" "$target"
        elif [ ! -e "$target" ] && [ ! -L "$target" ]; then
            /bin/busybox cp -a "$entry" "$target"
        fi
    done
}
copy_missing "$1" "$2"
EOF

        # build-images.sh creates this same builder when it is absent. Create
        # it here so the cache is ready before that script starts building.
        if ! docker buildx inspect hst_builder >/dev/null 2>&1; then
            builder_opts=()
            if [ -n "${HTTP_PROXY:-}" ]; then
                builder_opts+=(--driver-opt "env.http_proxy=$HTTP_PROXY")
            fi
            if [ -n "${HTTPS_PROXY:-}" ]; then
                builder_opts+=(--driver-opt "env.https_proxy=$HTTPS_PROXY")
            fi
            if [ -n "${NO_PROXY:-}" ]; then
                # --driver-opt parses CSV: quote the entire key=value field
                # and escape any quotes within the comma-separated value.
                builder_opts+=(--driver-opt "\"env.no_proxy=${NO_PROXY//\"/\"\"}\"")
            fi
            docker buildx create --name hst_builder --driver docker-container \
                "${builder_opts[@]}" --bootstrap
        fi

        cat > "$helper_dir/Dockerfile.hst_builder" <<'EOF'
FROM scratch
COPY busybox /bin/busybox
COPY copy-missing.sh /copy-missing.sh
SHELL ["/bin/busybox", "sh", "-c"]
ARG HST_CACHE_NONCE
RUN --mount=type=bind,from=seed,source=hst_builder,target=/seed,readonly \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/var/cache/downloads \
    set -e; \
    /bin/busybox sh /copy-missing.sh /seed/apt /var/cache/apt; \
    /bin/busybox sh /copy-missing.sh /seed/apt-lists /var/lib/apt; \
    /bin/busybox sh /copy-missing.sh /seed/downloads /var/cache/downloads
EOF

        cat > "$helper_dir/Dockerfile.default" <<'EOF'
FROM scratch
COPY busybox /bin/busybox
COPY copy-missing.sh /copy-missing.sh
SHELL ["/bin/busybox", "sh", "-c"]
ARG HST_CACHE_NONCE
RUN --mount=type=bind,from=seed,source=default,target=/seed,readonly \
    --mount=type=cache,target=/var/cache/downloads \
    --mount=type=cache,target=/var/cache/go-mod \
    set -e; \
    /bin/busybox sh /copy-missing.sh /seed/downloads /var/cache/downloads; \
    /bin/busybox sh /copy-missing.sh /seed/go-mod /var/cache/go-mod
EOF

        # The bind mounts keep the seed files out of the helper image layers.
        # Only the named BuildKit cache mounts receive the copied contents.
        docker buildx build --builder hst_builder --network none \
            --build-arg "HST_CACHE_NONCE=$helper_nonce" \
            --build-context "seed=$cache_dir" \
            --output type=cacheonly \
            --file "$helper_dir/Dockerfile.hst_builder" "$helper_dir"
        docker buildx build --builder default --network none \
            --build-arg "HST_CACHE_NONCE=$helper_nonce" \
            --build-context "seed=$cache_dir" \
            --output type=cacheonly \
            --file "$helper_dir/Dockerfile.default" "$helper_dir"
        ;;

esac
