terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 3
}

locals {
  model_bucket_name = "${var.model_bucket_name_prefix}-${random_id.bucket_suffix.hex}"
}


provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "run_api" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry_api" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild_api" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "container_repo" {
  location      = var.region
  repository_id = var.artifact_registry_repo_id
  format        = "DOCKER"
  description   = "Container images for Lab 6 FastAPI service"

  depends_on = [google_project_service.artifact_registry_api]
}

resource "google_storage_bucket" "model_bucket" {
  name                        = local.model_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  versioning {
    enabled = true
  }
}

resource "google_service_account" "app_sa" {
  account_id   = var.service_account_name
  display_name = "Lab 6 FastAPI app service account"
}

resource "google_project_iam_member" "sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_project_iam_member" "sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_cloud_run_v2_service" "inference_api" {
  name     = var.cloud_run_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.app_sa.email

    containers {
      image = var.cloud_run_image

      env {
        name  = "MODEL_BUCKET"
        value = google_storage_bucket.model_bucket.name
      }

      env {
        name  = "MODEL_OBJECT"
        value = var.model_object
      }
    }
  }

  depends_on = [google_project_service.run_api]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.inference_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
