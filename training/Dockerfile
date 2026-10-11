# Reproducible training environment.
#
#   docker build -t harvestshelf-train training/
#   docker run --rm -it -v "$PWD":/workspace -p 8888:8888 harvestshelf-train
#
# The repository is mounted at /workspace, so data/ and training/exports/
# are read and written on the host.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    TFHUB_CACHE_DIR=/workspace/training/.tfhub_cache

RUN apt-get update \
 && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 make \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

WORKDIR /workspace/training
CMD ["bash"]
