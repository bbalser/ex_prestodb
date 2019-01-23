defmodule Prestodb.MixProject do
  use Mix.Project

  def project do
    [
      app: :prestodb,
      version: "0.1.0",
      elixir: "~> 1.7",
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
      {:hackney, "~> 1.15"},
      {:jason, "~> 1.1"},
      {:mox, "~> 0.4.0", only: :test},
      {:bypass, "~> 1.0", only: :test}
    ]
  end
end
