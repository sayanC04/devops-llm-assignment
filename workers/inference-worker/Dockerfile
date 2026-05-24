FROM python:3.11-slim

WORKDIR /app

# 1. Install PyTorch CPU directly from the PyTorch index (avoids pip resolution delays)
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

# 2. Copy and install standard Python dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy worker script
COPY . .

# Set default env variables
ENV III_URL=ws://localhost:49134
ENV PYTHONUNBUFFERED=1

# Start the inference worker
CMD ["python", "inference_worker.py"]
