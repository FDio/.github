group "default" {
    targets = [
      "prod-x86_64",
      "prod-aarch64"
    ]
}

target "docker-metadata-action" {}

target "prod-x86_64" {
    inherits = ["docker-metadata-action"]
    dockerfile = "Dockerfile"
    platforms = [
      "linux/amd64"
    ]
    args = {
        BASE_IMAGE = "ubuntu:26.04"
    }
}

target "prod-aarch64" {
    inherits = ["docker-metadata-action"]
    dockerfile = "Dockerfile"
    platforms = [
      "linux/aarch64"
    ]
    args = {
        BASE_IMAGE = "ubuntu:26.04"
    }
}
