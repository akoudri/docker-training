#!/bin/bash

aws ecr get-login-password | docker login --username AWS --password-stdin $DOCKER_REGISTRY
docker push $DOCKER_REGISTRY/docker-training:1.0
