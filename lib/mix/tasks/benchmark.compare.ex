defmodule Mix.Tasks.Benchmark.Compare do
  @moduledoc "Compares benchmarks of specific HTTP servers"
  @shortdoc "Compares benchmarks of specific HTTP servers"

  use Mix.Task

  require Logger

  @requirements ["app.start"]
  @margin_of_error 0.1

  @impl Mix.Task
  def run(["--" <> _, _, _] = servers) do
    [results_a, results_b] = Mix.Task.run("benchmark", servers)

    compare(results_a, results_b)
  end

  def run([_, _] = servers), do: run(["--normal" | servers])
  def run(_), do: Mix.Shell.IO.error("usage: mix benchmark.compare <server_def> <server_def>")

  defp compare(results_a, results_b) do
    results =
      results_a
      |> Enum.map(fn result_a ->
        scenario = result_a.scenario
        result_b = Enum.find(results_b, &(&1.scenario == scenario))

        {scenario.protocol, scenario.endpoint, scenario.clients, scenario.concurrency,
         result_a.result, result_b.result}
      end)
      |> Enum.sort()
      |> Enum.map(fn {protocol, endpoint, clients, _concurrency, result_a, result_b} ->
        [
          protocol,
          endpoint,
          clients,
          compare(result_a, result_b, :reqs_per_sec_mean, true, "FASTER", "SLOWER"),
          compare(result_a, result_b, :memory_total, false, "LOWER", "HIGHER")
        ]
      end)

    server_a = List.first(results_a).server_def
    server_b = List.first(results_b).server_def

    summary = """
    **#{server_b.server} (#{server_b.treeish})** vs **#{server_a.server} (#{server_a.treeish})**

    | Protocol | Endpoint | # Clients | Reqs per sec (mean) | Total memory |
    | -------- | -------- | --------- | ------------------- | ------------ |
    #{Enum.map_join(results, "\n", &("| " <> Enum.join(&1, " | ") <> " |"))}
    """

    Logger.info("Writing summary to http-summary.md")

    File.write!("http-summary.md", summary)
  end

  defp compare(a, b, key, larger_is_better, positive_msg, negative_msg) do
    if a[key] == 0 do
      ":collision: ERROR"
    else
      ratio = b[key] / a[key]
      ratio_str = :erlang.float_to_binary(ratio, decimals: 2)

      cond do
        ratio < 1 - @margin_of_error && larger_is_better ->
          ":x: #{negative_msg} (#{ratio_str}x)"

        ratio < 1 - @margin_of_error && !larger_is_better ->
          ":white_check_mark: #{positive_msg} (#{ratio_str}x)"

        ratio > 1 + @margin_of_error && larger_is_better ->
          ":white_check_mark: #{positive_msg} (#{ratio_str}x)"

        ratio > 1 + @margin_of_error && !larger_is_better ->
          ":x: #{negative_msg} (#{ratio_str}x)"

        true ->
          ":ballot_box_with_check: IT'S A WASH (#{ratio_str}x)"
      end
    end
  end
end
