FROM python:3.6.1-alpine

WORKDIR /usr/src/app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY *.py .

EXPOSE 5000

CMD [ "python", "./docker_id.py" ]
