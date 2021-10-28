FROM ruby:2.7.2-slim-buster@sha256:bfebe6467a71a1bdf829d00dd60e25c27dea21d52ec04d1cb613184ab1922426 AS ruby-base

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
