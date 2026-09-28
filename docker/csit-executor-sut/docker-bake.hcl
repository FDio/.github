group "default" {
    targets = [
      "prod"
    ]
}

target "docker-metadata-action" {}

target "prod" {
    inherits = ["docker-metadata-action"]
    dockerfile = "Dockerfile"
    platforms = [
      "linux/amd64"
    ]
    args = {
        BASE_IMAGE = "ubuntu:24.04"
    }
}
