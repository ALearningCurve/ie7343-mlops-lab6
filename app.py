from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path
from typing import Any

import joblib
from fastapi import FastAPI, HTTPException
from google.cloud import storage
from pydantic import BaseModel, Field
from dotenv import load_dotenv


MODEL_DIR = Path("artifacts")
MODEL_PATH = MODEL_DIR / "classifier.joblib"

# Load .env for local development while preserving existing env vars.
load_dotenv(override=False)

app = FastAPI(title="Lab 6 Inference API", version="1.0.0")


class InferenceRequest(BaseModel):
    features: list[float] = Field(
        ...,
        description="List of 30 feature values for the breast cancer classifier.",
        min_length=1,
    )


class InferenceResponse(BaseModel):
    predicted_class: int
    probabilities: list[float]
    model_source: str


def ensure_model_available(model_path: Path) -> str:
    """Ensure the model exists locally, downloading from GCS if configured."""
    if model_path.exists():
        return "local"

    bucket_name = os.environ.get("MODEL_BUCKET")
    object_name = os.environ.get("MODEL_OBJECT", "models/classifier.joblib")
    if not bucket_name:
        raise RuntimeError(
            "Model file not found locally and MODEL_BUCKET is not configured."
        )

    model_path.parent.mkdir(parents=True, exist_ok=True)
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    blob.download_to_filename(str(model_path))
    return f"gcs://{bucket_name}/{object_name}"


@lru_cache(maxsize=1)
def load_model() -> tuple[Any, str]:
    """Load and cache the model to avoid reloading on every request."""
    source = ensure_model_available(MODEL_PATH)
    model = joblib.load(MODEL_PATH)
    return model, source


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "FastAPI MLOps Lab 6 service is running."}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/inference", response_model=InferenceResponse)
def inference(payload: InferenceRequest) -> InferenceResponse:
    model, model_source = load_model()

    expected_features = getattr(model, "n_features_in_", None)
    if expected_features is not None and len(payload.features) != int(expected_features):
        raise HTTPException(
            status_code=400,
            detail=(
                "Invalid feature vector length. "
                f"Expected {expected_features} values, received {len(payload.features)}."
            ),
        )

    prediction = model.predict([payload.features])[0]
    probabilities = model.predict_proba([payload.features])[0].tolist()

    return InferenceResponse(
        predicted_class=int(prediction),
        probabilities=[float(p) for p in probabilities],
        model_source=model_source,
    )