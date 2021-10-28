FROM ruby:2.7.4-slim-buster@sha256:afc5840d7214ce2f39f2ab18a32115a5b88b282394f286c00131f2799c49f76b AS ruby-base

ENV RUBY_BUNDLER_VERSION '2.2.30'
ENV BUNDLE_PATH /usr/local/bundle

RUN gem install bundler -v $RUBY_BUNDLER_VERSION

RUN apt-get update \
  && apt-get install -y --no-install-recommends libpq-dev \
  && rm -rf /var/lib/apt/lists/*

### dev-environment
FROM ruby-base AS dev-environment

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential curl git \
  && rm -rf /var/lib/apt/lists/*
