FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DYNAFACE_MODEL_PATH=/opt/dynaface-models

WORKDIR /app

# 1. Install necessary system binary dependencies for OpenCV and video rendering
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# 2. Copy the entire repository layout into /app to preserve dynamic path detection
COPY . /app

# 3. Install requirements and link editable libraries from the clean workspace root
RUN pip install --no-cache-dir -r /app/dynaface-mobile/google-remote-scripts/requirements.txt \
    && pip install --no-cache-dir -e /app/dynaface-main/dynaface-lib

# 4. Pre-download the deep-learning models into the cache directory during image assembly
# 4. Pre-download the deep-learning models into the cache directory during image assembly
RUN mkdir -p /opt/dynaface-models \
    && python -c "import sys; sys.path.insert(0, '/app/dynaface-main/dynaface-lib'); from dynaface import models; models.download_models('/opt/dynaface-models'); models.init_models('/opt/dynaface-models', 'cpu')"

# 🌟 5. FIX: Run your worker script directly using standard Python CLI invocation.
# Cloud Run Jobs passes your GCS path hook explicitly as a trailing argument!
ENTRYPOINT ["python", "google_remote_dynaface_worker.py"]