defmodule Mix.Tasks.Benchmark do
  @moduledoc "Runs benchmarks against specific HTTP servers"
  @shortdoc "Runs benchmarks against specific HTTP servers"

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([]),
    do: Mix.Shell.IO.error("usage: mix benchmark [--normal | --tiny | --huge] [server_def]*")

  def run(["--" <> profile | servers]) do
    servers
    |> Enum.map(&Benchmark.run(&1, String.to_atom(profile)))
    |> tap(fn results ->
      results
      |> List.flatten()
      |> Benchmark.CSVExport.export("http-benchmark.csv")
    end)
  end

  def run(servers), do: run(["--normal" | servers])
end
