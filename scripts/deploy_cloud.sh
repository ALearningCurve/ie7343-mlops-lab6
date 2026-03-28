#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/deploy_cloud.sh [--image IMAGE_URI] [--auto-approve]

Deploys Lab 6 infrastructure and Cloud Run service via Terraform, uploads
model artifacts to GCS, and runs a cloud inference smoke test.

If --image is omitted, the script bootstraps Artifact Registry via Terraform,
derives IMAGE_URI from Terraform output, and builds/pushes the image.

Options:
  --image IMAGE_URI   Prebuilt container image URI for Cloud Run
  --auto-approve      Pass -auto-approve to terraform apply
  -h, --help          Show this help
EOF
}

# # # # # # # # # # # # # # # # # # #
#           READ ARGUMENTS
# # # # # # # # # # # # # # # # # # # 

IMAGE_URI=""
TF_AUTO_APPROVE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      IMAGE_URI="$2"
      shift 2
      ;;
    --auto-approve)
      TF_AUTO_APPROVE="-auto-approve"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# # # # # # # # # # # # # # # # # # #
#        VALIDATE PREREQUISITES
# # # # # # # # # # # # # # # # # # # 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
ENV_FILE="${REPO_ROOT}/.env"
ENV_EXAMPLE_FILE="${REPO_ROOT}/.env.example"

for cmd in terraform gcloud uv curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
done

if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
  cp "${TF_DIR}/terraform.tfvars.example" "${TF_DIR}/terraform.tfvars"
  echo "Created ${TF_DIR}/terraform.tfvars from example. Please edit it, then re-run." >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${ENV_EXAMPLE_FILE}" "${ENV_FILE}"
  echo "Created ${ENV_FILE} from .env.example"
fi

upsert_env_var() {
  local key="$1"
  local value="$2"

  if grep -qE "^${key}=" "${ENV_FILE}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}


# # # # # # # # # # # # # # # # # # #
#         APPLY TF + SET VARS
# # # # # # # # # # # # # # # # # # # 

terraform -chdir="${TF_DIR}" init

# If image is not provided, bootstrap Artifact Registry and build/push one.
if [[ -z "$IMAGE_URI" ]]; then
  terraform -chdir="${TF_DIR}" apply ${TF_AUTO_APPROVE} \
    -target=google_project_service.artifact_registry_api \
    -target=google_project_service.cloudbuild_api \
    -target=google_artifact_registry_repository.container_repo \
    -var='cloud_run_image=bootstrap-placeholder'

  IMAGE_URI="$(terraform -chdir="${TF_DIR}" output -raw suggested_image_uri)"

  # Targeted applies do not always refresh all outputs. Derive project/region
  # from the image URI format: <region>-docker.pkg.dev/<project>/<repo>/<image>:<tag>
  REGION="${IMAGE_URI%%-docker.pkg.dev/*}"
  PROJECT_ID="$(echo "${IMAGE_URI}" | cut -d/ -f2)"

  # If outputs are available, prefer them.
  PROJECT_ID="$(terraform -chdir="${TF_DIR}" output -raw project_id 2>/dev/null || echo "${PROJECT_ID}")"
  REGION="$(terraform -chdir="${TF_DIR}" output -raw region 2>/dev/null || echo "${REGION}")"

  gcloud config set project "${PROJECT_ID}" >/dev/null
  gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
  gcloud builds submit --tag "${IMAGE_URI}" "${REPO_ROOT}"
fi

terraform -chdir="${TF_DIR}" apply ${TF_AUTO_APPROVE} -var="cloud_run_image=${IMAGE_URI}"

PROJECT_ID="$(terraform -chdir="${TF_DIR}" output -raw project_id)"
REGION="$(terraform -chdir="${TF_DIR}" output -raw region)"
MODEL_BUCKET="$(terraform -chdir="${TF_DIR}" output -raw model_bucket)"
SERVICE_URL="$(terraform -chdir="${TF_DIR}" output -raw cloud_run_url)"

gcloud config set project "${PROJECT_ID}" >/dev/null

# Keep local env in sync for local uv/docker runs.
upsert_env_var "MODEL_BUCKET" "${MODEL_BUCKET}"
upsert_env_var "GOOGLE_CLOUD_PROJECT" "${PROJECT_ID}"
unset GOOGLE_APPLICATION_CREDENTIALS || true

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "Warning: ADC not configured. Run: gcloud auth application-default login" >&2
fi

# # # # # # # # # # # # # # # # # # #
#         CREATE MODEL
# # # # # # # # # # # # # # # # # # # 

cd "${REPO_ROOT}"
uv sync
MODEL_BUCKET="${MODEL_BUCKET}" uv run python train_model.py


# # # # # # # # # # # # # # # # # # #
#         RUN SMOKE TEST
# # # # # # # # # # # # # # # # # # # 

TOKEN="$(gcloud auth print-identity-token)"
HEALTH_CODE="$(curl -s -H "Authorization: Bearer ${TOKEN}" -o /tmp/lab6-health.out -w "%{http_code}" "${SERVICE_URL}/health")"
if [[ "$HEALTH_CODE" != "200" ]]; then
  echo "Error: service health check failed with code ${HEALTH_CODE}" >&2
  cat /tmp/lab6-health.out >&2
  exit 1
fi

INFER_PAYLOAD='{
  "features": [
    17.99, 10.38, 122.8, 1001.0, 0.1184, 0.2776, 0.3001, 0.1471, 0.2419, 0.07871,
    1.095, 0.9053, 8.589, 153.4, 0.006399, 0.04904, 0.05373, 0.01587, 0.03003, 0.006193,
    25.38, 17.33, 184.6, 2019.0, 0.1622, 0.6656, 0.7119, 0.2654, 0.4601, 0.1189
  ]
}'

INFER_CODE="$(curl -s -o /tmp/lab6-infer.out -w "%{http_code}" -H "Authorization: Bearer ${TOKEN}" -X POST "${SERVICE_URL}/inference" -H "Content-Type: application/json" -d "${INFER_PAYLOAD}")"
if [[ "$INFER_CODE" != "200" ]]; then
  echo "Error: inference request failed with code ${INFER_CODE}" >&2
  cat /tmp/lab6-infer.out >&2
  exit 1
fi

echo
printf 'Deployment complete.\nProject: %s\nRegion: %s\nModel bucket: %s\nService URL: %s\n' \
  "${PROJECT_ID}" "${REGION}" "${MODEL_BUCKET}" "${SERVICE_URL}"
