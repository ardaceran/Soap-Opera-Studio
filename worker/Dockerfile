# Soap Opera Studio generation worker. Standard library only, no pip packages.
# FFmpeg assembles the episode video; DejaVu is the caption font.
FROM python:3.12-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY sos_worker ./sos_worker
COPY tests ./tests
ENV PYTHONUNBUFFERED=1
CMD ["python", "-m", "sos_worker"]
