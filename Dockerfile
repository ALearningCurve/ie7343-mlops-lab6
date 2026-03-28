FROM python:3.11-slim

WORKDIR /app

# Install uv package manager.
RUN pip install --no-cache-dir uv

# Copy lock metadata and install project deps into local .venv.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# Copy app code
COPY . .

# Re-sync after source copy so the project and locked deps are definitely present.
RUN uv sync --frozen --no-dev

# Use the uv-managed virtual environment by default.
ENV PATH="/app/.venv/bin:${PATH}"

# Expose port 8080 for Cloud Run compatibility
EXPOSE 8080

# Run FastAPI service
CMD ["uv", "run", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
