project_id               = "cheffy-483719"
region                   = "us-east1"
model_bucket_name_prefix = "ie7343-lab6-models"
service_account_name     = "lab6-fastapi-mlops-sa"
cloud_run_service_name   = "lab6-inference-api"
cloud_run_image          = "us-east1-docker.pkg.dev/cheffy-483719/lab6/lab6-api:latest"
model_object             = "models/classifier.joblib"
allow_unauthenticated    = false
