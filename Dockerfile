FROM trenpixster/elixir:1.1.1
MAINTAINER Bluek404 <i@bluek404.net>

ADD mix.exs /stepladder/
ADD lib /stepladder/
ADD config /stepladder/

WORKDIR /stepladder

ENV MIX_ENV prod

RUN mix deps.get && mix compile

CMD iex -S mix
