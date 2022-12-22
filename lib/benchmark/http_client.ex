defmodule Benchmark.HTTPClient do
  @moduledoc false

  require Logger

  @file_10k Path.join(:code.priv_dir(:benchmark), "random_10k")
  @file_10m Path.join(:code.priv_dir(:benchmark), "random_10m")

  def run(server_def, args) do
    profile = Keyword.get(args, :profile, "normal")
    Logger.info("Benchmarking #{server_def.server} (#{server_def.treeish}) #{profile} profile")

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
        concurrency <- build_concurrencies(args),
        clients <- build_clients(args),
        endpoint <- build_endpoints(args) do
      %{
        protocol: protocol,
        concurrency: concurrency,
        threads: build_threads(clients),
        clients: clients,
        endpoint: endpoint,
        upload_file: build_upload_file(args, endpoint),
        duration: build_duration(args, clients)
      }
    end
  end

  defp build_protocols(args) do
    args
    |> Keyword.get(:protocol, "http/1.1,h2c")
    |> String.split(",")
    |> List.delete("ws")
  end

  defp build_concurrencies(args) do
    if Keyword.get(args, :profile) == "huge", do: [1, 4, 16], else: [1]
  end

  defp build_clients(args) do
    case Keyword.get(args, :profile, "normal") do
      "tiny" -> [1, 4, 16]
      "normal" -> [1, 2, 4, 16, 64]
      "huge" -> [1, 2, 4, 16, 64, 256, 1024]
    end
  end

  defp build_threads(clients), do: min(clients, 32)

  defp build_endpoints(args) do
    case {Keyword.get(args, :profile), Keyword.get(args, :memory)} do
      {"tiny", "true"} -> ["memory_noop"]
      {"tiny", _} -> ["noop"]
      {_, "true"} -> ["memory_noop", "memory_upload", "memory_download", "memory_echo"]
      {_, _} -> ["noop", "upload", "download", "echo"]
    end
  end

  defp build_upload_file(args, endpoint) when endpoint in ["echo", "upload"] do
    if Keyword.get(args, :bigfile) == "true", do: @file_10m, else: @file_10k
  end

  defp build_upload_file(_args, _endpoint), do: nil

  defp build_duration(_args, clients) when clients > 64, do: {:count, 1_000_000}

  defp build_duration(args, _clients) do
    if Keyword.get(args, :profile) == "tiny", do: {:duration, 5, 1}, else: {:duration, 15, 5}
  end

  defp run_benchmark(scenario, server_def) do
    duration =
      case scenario.duration do
        {:count, count} ->
          ["-n", to_string(count)]

        {:duration, duration, warm_up} ->
          ["-D", to_string(duration), "--warm-up-time", to_string(warm_up)]
      end

    upload = if scenario.upload_file, do: ["-d", scenario.upload_file], else: []

    MuonTrap.cmd(
      "h2load",
      duration ++
        upload ++
        [
          "-p",
          scenario.protocol,
          "-m",
          to_string(scenario.concurrency),
          "-t",
          to_string(scenario.threads),
          "-c",
          to_string(scenario.clients),
          "http://#{server_def.hostname}:#{server_def.port}/#{scenario.endpoint}"
        ],
      stderr_to_stdout: true
    )
  end

  defp parse_output({output, 0}) do
    [status, _traffic, _min_max_headers, ttr, ttc, ttfb, reqs, _newline] =
      output
      |> String.split("\n")
      |> Enum.take(-8)

    process_status(status)
    |> Map.merge(process_statline(ttr, "time_to_request"))
    |> Map.merge(process_statline(ttc, "time_to_connect"))
    |> Map.merge(process_statline(ttfb, "time_to_first_byte"))
    |> Map.merge(process_statline(reqs, "reqs_per_sec"))
  end

  defp process_status("status codes: " <> status) do
    status
    |> String.split(",")
    |> Enum.map(&String.split(&1, " ", trim: true))
    |> Enum.map(fn [count, code] -> {:"status_#{code}", String.to_integer(count)} end)
    |> Enum.into(%{})
  end

  defp process_statline(<<_label::binary-17, stats::binary>>, name) do
    [min, max, mean, sd, _percentage] =
      stats
      |> String.split(" ", trim: true)
      |> Enum.map(&Float.parse/1)
      |> Enum.map(fn
        {value, "ms"} -> value * 1000
        {value, _} -> value
      end)

    %{"#{name}_min": min, "#{name}_max": max, "#{name}_mean": mean, "#{name}_sd": sd}
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
