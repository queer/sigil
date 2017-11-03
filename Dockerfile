FROM elixir:1.5.2-slim

# Install hex
RUN mix local.hex --force

# Install phx
RUN mix archive.install https://github.com/phoenixframework/archives/raw/master/phx_new-1.3.0.ez --force
RUN mkdir /app
RUN mix local.rebar --force

RUN apt-get update
RUn apt-get install -y git

# Copy our shit in 
COPY . /app
WORKDIR /app

# Build our shit
RUN mix deps.get

RUN mix deps.update violet eden

# Required for some weebsocket shit

RUN mix compile

CMD epmd -daemon && mix phx.server