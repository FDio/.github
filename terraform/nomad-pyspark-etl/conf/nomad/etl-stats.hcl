variable "datacenter" {
  # Set the `NOMAD_VAR_datacenter` environment variable to override the
  # default for the task.
  type    = string
  default = "yul1"
}

variable "namespace" {
  # Set the `NOMAD_VAR_namespace` environment variable to override the
  # default for the task.
  type    = string
  default = "etl"
}

variable "cron" {
  type = string
}

variable "constraint_arch" {
  # Set the `NOMAD_VAR_constraint_arch` environment variable to override the
  # default for the task.
  type    = string
  default = "amd64"
}

variable "constraint_class" {
  # Set the `NOMAD_VAR_constraint_class` environment variable to override the
  # default for the task.
  type    = string
  default = "builder"
}

variable "cpu" {
  # Set the `NOMAD_VAR_cpu` environment variable to override the
  # default for the task.
  type    = number
  default = 10000
}

variable "image" {
  # Set the `NOMAD_VAR_image` environment variable to override the
  # default for the task.
  type    = string
  default = "pmikus/docker-ubuntu-focal-aws-glue:latest"
}

variable "memory" {
  # Set the `NOMAD_VAR_memory` environment variable to override the
  # default for the task.
  type    = number
  default = 24000
}

variable "script_name" {
  # Set the `NOMAD_VAR_script_name` environment variable to override the
  # default for the task.
  type    = string
  default = "local"
}

job "etl-stats" {
  datacenters = [var.datacenter]
  type        = "batch"
  namespace   = var.namespace

  periodic {
    cron             = var.cron
    prohibit_overlap = true
    time_zone        = "UTC"
  }

  group "etl-stats" {
    restart {
      mode = "fail"
    }
    constraint {
      attribute = "$${attr.cpu.arch}"
      value     = var.constraint_arch
    }
    constraint {
      attribute = "$${node.class}"
      value     = var.constraint_class
    }
    task "etl-stats" {
      artifact {
        source      = "https://raw.githubusercontent.com/FDio/csit/master/csit.infra.etl/${var.script_name}.py"
        destination = "/home/hadoop/workspace"
      }
      artifact {
        source      = "https://raw.githubusercontent.com/FDio/csit/master/csit.infra.etl/${var.script_name}_sra.json"
        destination = "/home/hadoop/workspace"
      }
      driver = "docker"
      config {
        image   = "public.ecr.aws/glue/aws-glue-libs:5"
        args = [
            "-c",
            "ls -al /home/hadoop/workspace; python3 -m pip install awswrangler==3.17.1; spark-submit --driver-memory 16g --executor-memory 16g --executor-cores 4 /home/hadoop/workspace/stats.py"
        ]
        work_dir = "/home/hadoop/workspace"
      }
      template {
        destination = "${NOMAD_SECRETS_DIR}/.env"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs" -}}
{{- range $k, $v := . }}
{{ $k }}={{ $v }}
{{- end }}
{{- end }}
EOT
      }
      resources {
        cpu    = var.cpu
        memory = var.memory
      }
    }
  }
}
