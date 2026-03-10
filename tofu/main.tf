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

resource "postgresql_role" "web_anon" {
  name     = "web_anon"
  login    = false
  depends_on = [postgresql_database.postgrest]
}

resource "postgresql_grant" "web_anon_schema_usage" {
  database    = postgresql_database.postgrest.name
  role        = postgresql_role.web_anon.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/config")
}

resource "kubernetes_namespace" "postgrest" {
  metadata {
    name = "postgrest"
  }

  depends_on = [terraform_data.k3d_cluster]
}

resource "kubernetes_secret" "postgrest_db" {
  metadata {
    name      = "postgrest-secret"
    namespace = kubernetes_namespace.postgrest.metadata[0].name
  }

  data = {
    PGRST_DB_URI       = "postgres://postgrest_admin:${var.postgres_password_postgrest}@host.k3d.internal:${var.postgres_port}/postgrest"
    PGRST_DB_ANON_ROLE = "web_anon"
    PGRST_DB_SCHEMAS   = "public"
    PGRST_SERVER_PORT  = "3000"
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace.postgrest,
    postgresql_role.postgrest_superuser,
    postgresql_role.web_anon
  ]
}

resource "kubernetes_deployment" "postgrest" {
  metadata {
    name      = "postgrest"
    namespace = kubernetes_namespace.postgrest.metadata[0].name
    labels = {
      app = "postgrest"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "postgrest"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgrest"
        }
      }

      spec {
        container {
          name  = "postgrest"
          image = "postgrest/postgrest:v14.1"

          port {
            container_port = 3000
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.postgrest_db.metadata[0].name
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret.postgrest_db]
}

resource "kubernetes_service" "postgrest" {
  metadata {
    name      = "postgrest"
    namespace = kubernetes_namespace.postgrest.metadata[0].name
  }

  spec {
    selector = {
      app = "postgrest"
    }

    port {
      port        = 80
      target_port = 3000
    }
  }

  depends_on = [kubernetes_deployment.postgrest]
}

resource "kubernetes_ingress_v1" "postgrest" {
  metadata {
    name      = "postgrest"
    namespace = kubernetes_namespace.postgrest.metadata[0].name
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.postgrest.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.postgrest]
}

resource "kubernetes_job_v1" "seed_data" {
  metadata {
    name      = "seed-postgrest-data"
    namespace = kubernetes_namespace.postgrest.metadata[0].name
  }

  spec {
    backoff_limit = 3

    template {
      metadata {}

      spec {
        restart_policy = "Never"

        container {
          name  = "psql"
          image = "postgres:16-alpine"

          env {
            name  = "PGPASSWORD"
            value = var.postgres_password_postgrest
          }

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            psql -h host.k3d.internal -p ${var.postgres_port} -U postgrest_admin -d postgrest <<'SQL'
            CREATE TABLE IF NOT EXISTS public.todos (
              id serial PRIMARY KEY,
              task text NOT NULL,
              done boolean NOT NULL DEFAULT false
            );

            INSERT INTO public.todos (task, done)
            VALUES
              ('finish pipekit take-home', false),
              ('verify postgrest endpoint', true);

            GRANT SELECT ON public.todos TO web_anon;
            SQL
            EOT
          ]
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment.postgrest,
    postgresql_grant.web_anon_schema_usage
  ]
}