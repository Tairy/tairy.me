FROM ruby:2.4.1
MAINTAINER Tairy <tairyguo@gmail.com>

RUN gem sources --add https://gems.ruby-china.org/ --remove https://rubygems.org/ \
    && gem install bundler

WORKDIR /working

EXPOSE 4000
CMD bundler install && bundle exec jekyll serve -H 0.0.0.0 --force_polling