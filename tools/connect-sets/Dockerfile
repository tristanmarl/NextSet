FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY sync.py archive.py liftosaur.py ./
RUN useradd -u 1000 -m app && mkdir /data && chown app /data
USER app
ENV DATA=/data PYTHONUNBUFFERED=1
CMD ["python", "sync.py", "loop"]
