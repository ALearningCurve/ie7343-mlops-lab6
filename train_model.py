from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import joblib
from dotenv import load_dotenv
from google.cloud import storage
from sklearn.datasets import load_breast_cancer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


ARTIFACT_DIR = Path("artifacts")
MODEL_PATH = ARTIFACT_DIR / "classifier.joblib"
METRICS_PATH = ARTIFACT_DIR / "metrics.json"

# Load .env for local development while preserving existing env vars.
load_dotenv(override=False)


def build_model() -> Pipeline:
    """Create a simple classification pipeline."""
    return Pipeline(
        steps=[
            ("scaler", StandardScaler()),
            ("classifier", LogisticRegression(max_iter=1000, random_state=42)),
        ]
    )


def train() -> tuple[Pipeline, dict[str, Any]]:
    """Train a binary classifier on a public sklearn dataset."""
    X, y = load_breast_cancer(return_X_y=True)
    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=0.2,
        random_state=42,
        stratify=y,
    )

    model = build_model()
    model.fit(X_train, y_train)

    predictions = model.predict(X_test)
    metrics: dict[str, Any] = {
        "dataset": "sklearn_breast_cancer",
        "accuracy": float(accuracy_score(y_test, predictions)),
        "classification_report": classification_report(
            y_test, predictions, output_dict=True
        ),
        "feature_count": int(X_train.shape[1]),
        "train_rows": int(X_train.shape[0]),
        "test_rows": int(X_test.shape[0]),
    }
    return model, metrics


def save_artifacts(model: Pipeline, metrics: dict[str, Any]) -> None:
    """Persist model and metrics for local use and deployment."""
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, MODEL_PATH)
    METRICS_PATH.write_text(json.dumps(metrics, indent=2), encoding="utf-8")


def upload_to_gcs(model_path: Path) -> str:
    """Upload the model artifact to Google Cloud Storage."""
    bucket_name = os.environ.get("MODEL_BUCKET")
    object_name = os.environ.get("MODEL_OBJECT", "models/classifier.joblib")
    if not bucket_name:
        raise RuntimeError("MODEL_BUCKET environment variable is required for upload.")

    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    blob.upload_from_filename(str(model_path))
    return f"gcs://{bucket_name}/{object_name}"


def main() -> None:
    model, metrics = train()
    save_artifacts(model, metrics)
    gcs_uri = upload_to_gcs(MODEL_PATH)

    output = {
        "model_path": str(MODEL_PATH),
        "metrics_path": str(METRICS_PATH),
        "gcs_uri": gcs_uri,
        "accuracy": metrics["accuracy"],
    }
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
