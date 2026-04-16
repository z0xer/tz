# Проблемы в исходном Dockerfile

Исходный Dockerfile:
FROM ubuntu:latest
RUN apt-get update && apt-get install -y python3 python3-pip
COPY . /app
WORKDIR /app
RUN pip3 install -r requirements.txt
ENV DATABASE_PASSWORD=supersecret123
ENV API_KEY=sk-prod-abc123xyz
EXPOSE 8080
CMD ["python3", "app.py"]

## Проблема 1: Секреты прямо в Dockerfile (critical)
ENV DATABASE_PASSWORD=supersecret123
ENV API_KEY=sk-prod-abc123xyz

Любой может сделать docker inspect и увидеть пароли.
Решение: передавать через docker run -e или Vault.

## Проблема 2: latest вместо конкретной версии (high)
FROM ubuntu:latest

Сегодня latest — это 22.04, завтра — 24.04. Сборка сломается.
Либо же может возникнуть какие то уязвимости и ты скачаешь latest
Решение: FROM python:3.11-slim-bookworm (конкретная версия).

## Проблема 3: Всё работает от root (high)
Если хакер взломает приложение — получит root в контейнере.
А дальше он может выбраться на саму машинку если есть какие то misconfigs
Решение: создать обычного юзера и переключиться на него (USER).

## Проблема 4: Тяжёлый образ ubuntu (meduim)
ubuntu — 75МБ лишних пакетов. Больше пакетов = больше уязвимостей.
Решение: python:3.11-slim-bookworm (лёгкий образ).

## Проблема 5: Нет .dockerignore (meduim)
COPY . /app копирует ВСЁ: .git, .env, тесты, кэш.
В .git может быть история со старыми паролями.
Решение: создать .dockerignore.
