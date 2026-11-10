FROM python:3.12-slim

# A release is an image tag, so the version has to be part of the image
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION

WORKDIR /app
COPY server.py .
USER nobody
EXPOSE 8000
CMD ["python", "-u", "server.py"]
