defmodule Prestodb.MixProject do
  use Mix.Project

  def project do
    [
      app: :prestodb,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Prestodb.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tesla, "~> 1.2"},
      {:jason, "~> 1.1"},
      {:httpoison, "~> 1.5"}
    ]
  end
end
