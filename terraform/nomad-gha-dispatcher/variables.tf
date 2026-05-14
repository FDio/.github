# Nomad
variable "datacenters" {
  description = "Specifies the list of DCs to be considered placing this task."
  type        = list(string)
  default     = ["yul1"]
}

variable "cpu" {
  description = "Specifies the CPU required to run this task in MHz."
  type        = number
  default     = 12000
}

variable "image" {
  description = "Specifies the Docker image to run."
  type        = string
  default     = "pmikus/docker-gha-dispatcher"
}

variable "job_name" {
  description = "Specifies a name for the job."
  type        = string
  default     = "gha-dispatcher"
}

variable "memory" {
  description = "Specifies the memory required in MB."
  type        = number
  default     = 8000
}
variable "node_pool" {
  description = "Specifies the node pool to place the job in."
  type        = string
  default     = "default"
}

variable "region" {
  description = "The region in which to execute the job."
  type        = string
  default     = "global"
}

variable "type" {
  description = "Specifies the Nomad scheduler to use."
  type        = string
  default     = "service"
}

variable "dispatchers" {
  type = list(object({
    id         = number
    namespace  = string
    repository = string
    version    = string
  }))
  default = [
    {
      id         = 3
      namespace  = "prod"
      repository = "fdio-csit"
      version    = "2.6"
    },
    {
      id         = 4
      namespace  = "prod"
      repository = "fdio-vpp"
      version    = "2.6"
    },
    {
      id         = 5
      namespace  = "sandbox"
      repository = "fdio-csit"
      version    = "2.6"
    },
    {
      id         = 6
      namespace  = "sandbox"
      repository = "fdio-vpp"
      version    = "2.6"
    }
  ]
}
