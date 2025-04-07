FROM python:3.8-slim-buster
LABEL description="My simple server"

WORKDIR /python-docker
COPY . .
RUN pip3 install -r requirements.txt
EXPOSE 5000
CMD ["python3", "-m", "flask", "run", "--host=0.0.0.0", "--port=5000"]

