FROM public.ecr.aws/docker/library/python:3.12-slim

RUN pip install --no-cache-dir pytest==8.4.1 numpy==2.2.6 Pillow==11.3.0 scipy==1.15.3 PyYAML==6.0.2

COPY . /tests
