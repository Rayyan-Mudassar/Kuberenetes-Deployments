FROM python:3.11-slim

WORKDIR /app

# Create a non-root user (same hardening pattern you used before)
RUN useradd -m appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

USER appuser

EXPOSE 5000

CMD ["python", "app.py"]
