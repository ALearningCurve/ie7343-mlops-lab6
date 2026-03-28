variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "region" {
  description = "Default region for resources"
  type        = string
  default     = "us-east1"
}

variable "model_bucket_name_prefix" {
  description = "Prefix for model artifact bucket; Terraform appends a random suffix"
  type        = string
  default     = "ie7343-lab6-models"
}

variable "service_account_name" {
  description = "Service account id (without domain)"
  type        = string
  default     = "lab6-fastapi-mlops-sa"
}

variable "cloud_run_service_name" {
  description = "Cloud Run service name"
  type        = string
  default     = "lab6-inference-api"
}

variable "artifact_registry_repo_id" {
  description = "Artifact Registry repository id for Docker images"
  type        = string
  default     = "lab6-images"
}

variable "image_name" {
  description = "Container image name inside Artifact Registry"
  type        = string
  default     = "lab6-api"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

variable "cloud_run_image" {
  description = "Container image URI used by Cloud Run (must already exist)"
  type        = string
}

variable "model_object" {
  description = "Path to the model object in the model bucket"
  type        = string
  default     = "models/classifier.joblib"
}

variable "allow_unauthenticated" {
  description = "Whether to allow public unauthenticated invocation"
  type        = bool
  default     = false
}
