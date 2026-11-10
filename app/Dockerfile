FROM python:3.12-slim
WORKDIR /app
COPY server.py .
USER nobody
EXPOSE 8000
CMD ["python", "-u", "server.py"]
