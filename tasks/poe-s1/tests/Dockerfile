FROM public.ecr.aws/docker/library/python:3.12-slim

RUN pip install --no-cache-dir pytest==9.0.2 pytest-asyncio==1.3.0 pytest-cov==7.0.0 pytest-rerunfailures==16.1 virtualenv==20.38.0 pastel==0.2.1 pyyaml==6.0.3 tomli==2.4.0 poetry-core==2.3.1

ENV PYTHONPATH=/workspace
COPY hidden/tests/fixtures/packages/poe_test_helpers /opt/poe_test_helpers
RUN pip install --no-cache-dir --no-build-isolation /opt/poe_test_helpers \
 && mkdir -p /opt/wheelhouse \
 && pip download -q -d /opt/wheelhouse poetry==1.8.2 \
 && pip download -q -d /opt/wheelhouse poetry==2.0.0 \
 && pip download -q -d /opt/wheelhouse poetry-core pip setuptools wheel virtualenv
ENV PIP_FIND_LINKS=/opt/wheelhouse PIP_NO_INDEX=1

COPY . /tests
