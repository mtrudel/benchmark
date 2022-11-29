defmodule Mix.Tasks.Benchmark.Compare do
  @moduledoc "Compares benchmarks of specific HTTP servers"
  @shortdoc "Compares benchmarks of specific HTTP servers"

  use Mix.Task

  require Logger

  @requirements ["app.start"]
  @margin_of_error 0.05

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

        [
          scenario.protocol,
          scenario.endpoint,
          scenario.concurrency,
          scenario.clients,
          result_a.result,
          result_b.result
        ]
      end)
      |> Enum.sort()
      |> Enum.group_by(&hd/1, &tl/1)

    server_a = List.first(results_a).server_def
    server_b = List.first(results_b).server_def

    summary = """
    # #{server_b.server} (#{server_b.treeish}) vs #{server_a.server} (#{server_a.treeish})

    #{results |> Enum.map(fn {protocol, results} -> """
      ## #{protocol}

      #{graph(results, protocol, server_a, server_b)}

      #{tabulate(results)}

      """ end)}
    """

    Logger.info("Writing summary to http-summary.md")

    File.write!("http-summary.md", summary)
  end

  defp tabulate(results) do
    results =
      results
      |> Enum.map(fn [endpoint, concurrency, clients, result_a, result_b] ->
        [
          endpoint,
          concurrency,
          clients,
          compare(result_a, result_b, :reqs_per_sec_mean, true, "FASTER", "SLOWER"),
          compare(result_a, result_b, :memory_total, false, "LOWER", "HIGHER")
        ]
      end)

    """
    | Endpoint | Concurrency | # Clients | Reqs per sec (mean) | Total memory |
    | -------- | ----------- | --------- | ------------------- | ------------ |
    #{Enum.map_join(results, "\n", &("| " <> Enum.join(&1, " | ") <> " |"))}
    """
  end

  defp graph(results, protocol, server_a, server_b) do
    results
    |> Enum.group_by(&Enum.at(&1, 1))
    |> Enum.map(fn {concurrency, results} ->
      # Not the best way to do this
      clients = results |> Enum.map(&Enum.at(&1, 2)) |> Enum.uniq()

      results_by_endpoint =
        results
        |> Enum.group_by(&Enum.at(&1, 0), &Enum.take(&1, -2))
        |> Enum.map(fn {endpoint, results} ->
          results_a = results |> Enum.map(&Enum.at(&1, 0)) |> Enum.map(& &1[:reqs_per_sec_mean])
          results_b = results |> Enum.map(&Enum.at(&1, 1)) |> Enum.map(& &1[:reqs_per_sec_mean])

          results =
            Enum.zip_with(results_a, results_b, fn
              0, _ -> 1
              0.0, _ -> 1
              a, b -> b / a
            end)

          {endpoint, results}
        end)

      graph_data = %{
        type: "line",
        options: %{
          title: %{
            display: true,
            text: [
              "#{server_b.server}@#{server_b.treeish} vs. #{server_a.server}@#{server_a.treeish}",
              "#{protocol} @ #{concurrency} concurrency, requests per second"
            ]
          },
          scales: %{
            xAxes: [
              %{
                scaleLabel: %{
                  display: true,
                  labelString: "Number of Clients"
                }
              }
            ],
            yAxes: [
              %{
                scaleLabel: %{
                  display: true,
                  labelString: "Difference"
                }
              }
            ]
          }
        },
        data: %{
          labels: clients,
          datasets:
            Enum.map(results_by_endpoint, fn {endpoint, results} ->
              %{label: endpoint, data: results, fill: false}
            end)
        }
      }

      uri =
        "https://quickchart.io/chart?width=500&height=300&c=#{Jason.encode!(graph_data)}"
        |> URI.encode()

      "![](#{uri})\n"
    end)
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
