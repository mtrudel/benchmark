defmodule Benchmark.MixProject do
  use Mix.Project

  def project do
    [
      app: :benchmark,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Benchmark.Application, []}
    ]
  end

  defp deps do
    [
      {:finch, "~> 0.13"},
      {:mint_web_socket, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:muontrap, "~> 1.3.3"},
      {:csv, "~> 3.0"}
    ]
  end
end
