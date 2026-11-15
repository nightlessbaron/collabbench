FROM public.ecr.aws/docker/library/python:3.11-slim

RUN pip install --no-cache-dir pydantic==2.5.3 pydantic-core==2.14.6 annotated-types==0.6.0 typing-extensions==4.10.0 databases==0.7.0 SQLAlchemy==1.4.52 greenlet==3.0.3 aiosqlite==0.19.0 asyncpg==0.28.0 PyMySQL==1.1.0 cryptography==41.0.7 orjson==3.9.15 fastapi==0.109.2 starlette==0.36.3 httpx==0.24.1 httpcore==0.17.3 anyio==4.3.0 sniffio==1.3.1 h11==0.14.0 idna==3.6 certifi==2024.2.2 asgi-lifespan==2.1.0 pydantic-extra-types==2.6.0 nest-asyncio==1.6.0 pytest==7.4.4 pytest-asyncio==0.21.1 pluggy==1.4.0 iniconfig==2.0.0 packaging==24.0

RUN mkdir -p "$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')/ormar-0.12.2.dist-info" && printf 'Metadata-Version: 2.1\nName: ormar\nVersion: 0.12.2\n' > "$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')/ormar-0.12.2.dist-info"/METADATA

COPY . /tests
