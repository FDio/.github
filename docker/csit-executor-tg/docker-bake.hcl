group "default" {
    targets = [
      "prod-x86_64"
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
        BASE_IMAGE = "ubuntu:22.04"
    }
}
