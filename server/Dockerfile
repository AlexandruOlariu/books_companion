FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini .
COPY migrations migrations
COPY app app

RUN useradd --system --no-create-home app
USER app

# --proxy-headers: nginx on the same host sets X-Forwarded-For. The published
# port is bound to 127.0.0.1 only (docker-compose.yml), so only nginx can send
# that header and trusting it is safe.
# One worker is plenty here; rate limits live in Postgres, so more would be safe.
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips='*'"]
