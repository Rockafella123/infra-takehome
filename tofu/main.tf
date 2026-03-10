provider "docker" {}

resource "terraform_data" "k3d_cluster" {
  input = {
    name  = var.k3d_cluster_name
    image = "rancher/k3s:${var.k3s_version}"
  }

  provisioner "local-exec" {
    command = "k3d cluster create ${self.input.name} --image ${self.input.image} --servers 1 --agents 0 -p '8080:80@loadbalancer'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete ${self.input.name}"
  }
}

resource "docker_image" "postgres" {
  name         = "postgres:16-alpine"
  keep_locally = true
}

resource "docker_container" "postgres" {
  name  = "postgres-infra-takehome"
  image = docker_image.postgres.image_id

  env = [
    "POSTGRES_PASSWORD=${var.postgres_password}",
    "POSTGRES_DB=app",
  ]

  ports {
    internal = 5432
    external = var.postgres_port
  }

  volumes {
    volume_name    = docker_volume.postgres_data.name
    container_path = "/var/lib/postgresql/data"
  }

  restart = "unless-stopped"
}

resource "docker_volume" "postgres_data" {
  name = "postgres-infra-takehome-data"
}

provider "postgresql" {
  host     = "localhost"
  port     = var.postgres_port
  username = "postgres"
  password = var.postgres_password
  sslmode  = "disable"
}

resource "postgresql_database" "postgrest" {
  name       = "postgrest"
  depends_on = [docker_container.postgres]
}

resource "postgresql_role" "postgrest_superuser" {
  name      = "postgrest_admin"
  login     = true
  password  = var.postgres_password_postgrest
  superuser = true
  depends_on = [postgresql_database.postgrest]
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "postgrest" {
  metadata {
    name = "postgrest"
  }
}

resource "kubernetes_secret" "postgrest_db" {
  metadata {
    name      = "postgrest-secret"
    namespace = kubernetes_namespace.postgrest.metadata[0].name
  }

  data = {
    PGRST_DB_URI = base64encode(
      "postgres://postgrest_admin:${var.postgres_password_postgrest}@host.docker.internal:5432/postgrest"
    )
  }

  type = "Opaque"
}

