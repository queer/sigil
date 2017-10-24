defmodule Sigil.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sigil,
      version: "0.0.1",
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Sigil.Application, []},
      extra_applications: [:logger, :runtime_tools, :httpotion, :redix]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:distillery, "~> 1.5.2"},
      {:phoenix, "~> 1.3.0"},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_html, "~> 2.10"},
      {:phoenix_live_reload, "~> 1.0", only: :dev},
      {:gettext, "~> 0.11"},
      {:cowboy, "~> 1.0"},
      {:httpotion, "~> 3.0.2"},
      {:redix, ">= 0.0.0"},
      # TODO: Write custom pool?
      # https://github.com/opendoor-labs/redix_pool
      {:redix_pool, "~> 0.1.0"},
      {:violet, github: "queer/violet"},
      {:eden, github: "queer/eden"}
    ]
  end
end
