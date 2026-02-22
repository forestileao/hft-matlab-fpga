FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    ghdl \
    git \
    pkg-config \
    libboost-all-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
