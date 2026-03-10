variable "k3d_cluster_name" {
  description = "Name of the k3d cluster"
  type        = string
  default     = "infra-takehome"
}

variable "k3s_version" {
  description = "K3s image tag to use for cluster nodes"
  type        = string
  default     = "v1.35.2-k3s1"
}

variable "postgres_password" {
  description = "Password for the PostgreSQL instance"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "postgres_password_postgrest" {
  description = "Password for the PostgREST user"
  type        = string
  default     = "postgrest"
  sensitive   = true
}

variable "postgres_port" {
  description = "Host port to expose PostgreSQL on"
  type        = number
  default     = 5432
}
