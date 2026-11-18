# Soap Opera Studio generation worker. Standard library only, no pip packages yet.
FROM python:3.12-slim
WORKDIR /app
COPY sos_worker ./sos_worker
COPY tests ./tests
ENV PYTHONUNBUFFERED=1
CMD ["python", "-m", "sos_worker"]
