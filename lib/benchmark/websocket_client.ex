defmodule Benchmark.WebSocketClient do
  @moduledoc false

  require Logger

  def run(server_def, args) do
    profile = Keyword.get(args, :profile, "normal")

    Logger.info(
      "Benchmarking #{server_def.server} (#{server_def.treeish}) #{profile} profile (WebSocket)"
    )

    build_scenarios(args)
    |> Enum.map(fn scenario ->
      Logger.info(
        "Running #{scenario.protocol} with #{scenario.clients} clients against #{scenario.endpoint}"
      )

      reset_server_stats(server_def)

      result =
        scenario
        |> run_benchmark(server_def)
        |> parse_output()
        |> Map.merge(get_server_stats(server_def))

      %{server_def: server_def, scenario: scenario, result: result}
    end)
  end

  defp build_scenarios(args) do
    for protocol <- build_protocols(args),
        clients <- build_clients(args),
        endpoint <- build_endpoints(args) do
      %{
        protocol: protocol,
        concurrency: 1,
        threads: clients,
        clients: clients,
        endpoint: endpoint,
        count: build_count(args, clients),
        upload: build_upload(args, endpoint)
      }
    end
  end

  defp build_protocols(args) do
    args
    |> Keyword.get(:protocol, "http/1.1,h2c,ws")
    |> String.split(",")
    |> List.delete("http/1.1")
    |> List.delete("h2c")
  end

  defp build_clients(args) do
    case Keyword.get(args, :profile, "normal") do
      "tiny" -> [1, 4]
      "normal" -> [1, 4, 16, 64, 256]
      "huge" -> [1, 16, 64, 256, 1024, 4096]
    end
  end

  defp build_endpoints(args) do
    case {Keyword.get(args, :profile), Keyword.get(args, :memory)} do
      {"tiny", "true"} -> ["memory_noop"]
      {"tiny", _} -> ["noop", "upload"]
      {_, "true"} -> ["memory_noop", "memory_upload", "memory_download", "memory_echo"]
      {_, _} -> ["noop", "upload", "download", "echo"]
    end
  end

  defp build_count(_args, clients) do
    max(div(4096, clients), 1)
  end

  defp build_upload(args, endpoint) when endpoint in ["echo", "upload"] do
    if Keyword.get(args, :bigfile) == "true",
      do: String.duplicate("a", 10_000_000),
      else: String.duplicate("a", 10_000)
  end

  defp build_upload(_args, _endpoint), do: nil

  defp run_benchmark(scenario, server_def) do
    opts = %{
      hostname: server_def.hostname,
      port: server_def.port,
      endpoint: scenario.endpoint,
      count: scenario.count,
      upload: scenario.upload
    }

    1..scenario.clients
    |> Task.async_stream(WebSocketClientWorker, :run, [opts], ordered: false, timeout: 600_000)
    |> Enum.map(fn {:ok, map} -> map end)
  end

  defp parse_output(output) do
    result =
      output
      |> Enum.reduce(%{}, fn elem, acc ->
        reqs_per_sec = 1_000_000 / (elem.sum / elem.count)

        acc
        |> Map.update(:reqs_per_sec_min, reqs_per_sec, &min(&1, reqs_per_sec))
        |> Map.update(:reqs_per_sec_max, reqs_per_sec, &max(&1, reqs_per_sec))
        |> Map.update(:reqs_per_sec_mean, elem.sum, &(&1 + elem.sum))
        |> Map.update(:status_2xx, elem.successful, &(&1 + elem.successful))
        |> Map.update(:status_5xx, elem.failed, &(&1 + elem.failed))
        |> Map.update(:count, elem.count, &(&1 + elem.count))
      end)

    Map.update(result, :reqs_per_sec_mean, 0, &(1_000_000 / (&1 / result.count)))
  end

  defp reset_server_stats(server_def) do
    Finch.build(:get, "http://#{server_def.hostname}:#{server_def.port}/reset_stats")
    |> Finch.request(BenchmarkFinch)
    |> case do
      {:ok, %Finch.Response{body: "OK"}} -> :ok
    end
  end

  defp get_server_stats(server_def) do
    Finch.build(:get, "http://#{server_def.hostname}:#{server_def.port}/stats")
    |> Finch.request(BenchmarkFinch)
    |> case do
      {:ok, %Finch.Response{body: body}} ->
        Jason.decode!(body, keys: :atoms)
    end
  end
end
