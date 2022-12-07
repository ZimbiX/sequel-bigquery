FROM ruby:3.1.3-slim-bullseye@sha256:a6f940b1fca8a057561ac86f431539df2e77b954370fa17348f5a5ec3cba1cad AS ruby-base

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
