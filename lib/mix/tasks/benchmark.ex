defmodule Mix.Tasks.Benchmark do
  @moduledoc "Compares benchmarks of specific HTTP servers"
  @shortdoc "Compares benchmarks of specific HTTP servers"

  use Mix.Task

  require Logger

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {args, servers, _} = OptionParser.parse(args, switches: [])

    [results_a, results_b] =
      servers
      |> Enum.map(&Benchmark.run(&1, args))
      |> tap(fn results ->
        results
        |> List.flatten()
        |> Benchmark.CSVExport.export("http-benchmark.csv")
      end)

    compare(results_a, results_b)
  end

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

      """ end)}
    """

    Logger.info("Writing summary to http-summary.md")

    File.write!("http-summary.md", summary)
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
              nil, _ -> 0
              0, _ -> 0
              0.0, _ -> 0
              _, nil -> 0
              a, b -> 100 * b / a - 100
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
            x: %{
              scaleLabel: %{
                display: true,
                labelString: "Number of Clients"
              }
            },
            y: %{
              scaleLabel: %{
                display: true,
                labelString: "% Difference"
              },
              suggestedMin: -25,
              suggestedMax: 25
            }
          }
        },
        data: %{
          labels: clients,
          datasets:
            Enum.map(results_by_endpoint, fn {endpoint, results} ->
              %{label: endpoint, data: results, fill: "origin"}
            end)
        }
      }

      uri =
        "https://quickchart.io/chart?width=500&height=300&c=#{Jason.encode!(graph_data)}"
        |> URI.encode()

      "![](#{uri})\n"
    end)
  end
end
