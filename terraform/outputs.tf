output "model_bucket" {
  value       = google_storage_bucket.model_bucket.name
  description = "Name of bucket for model artifacts"
}

output "service_account_email" {
  value       = google_service_account.app_sa.email
  description = "Service account email for deployment"
}

output "cloud_run_service_name" {
  value       = google_cloud_run_v2_service.inference_api.name
  description = "Cloud Run service name"
}

output "cloud_run_url" {
  value       = google_cloud_run_v2_service.inference_api.uri
  description = "Cloud Run service URL"
}

output "project_id" {
  value       = var.project_id
  description = "GCP project id"
}

output "region" {
  value       = var.region
  description = "GCP region"
}

output "artifact_registry_repository" {
  value       = google_artifact_registry_repository.container_repo.repository_id
  description = "Artifact Registry repository id used for container images"
}

output "suggested_image_uri" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/${var.image_name}:${var.image_tag}"
  description = "Suggested image URI for build and Cloud Run deployment"
}
