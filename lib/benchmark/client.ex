defmodule Benchmark.Client do
  @moduledoc false

  require Logger

  @file_10k Path.join(:code.priv_dir(:benchmark), "random_10k")
  @file_10m Path.join(:code.priv_dir(:benchmark), "random_10m")

  def run(server_def, profile) do
    Logger.info(
      "Benchmarking #{server_def.server} (#{server_def.treeish}) using #{profile} profile"
    )

    build_scenarios(profile)
    |> Enum.map(fn scenario ->
      Logger.info(
        "Running #{scenario.protocol} with #{scenario.clients} clients against #{scenario.endpoint}"
      )

      reset_server_stats(server_def)

      result =
        scenario
        |> run_benchmark(server_def, profile)
        |> parse_output()
        |> Map.merge(get_server_stats(server_def))

      %{server_def: server_def, scenario: scenario, result: result}
    end)
  end

  defp build_scenarios(normal) when normal in [:normal, :normal_bigfile] do
    do_build_scenarios(
      protocols: ["http/1.1", "h2c"],
      clients_and_threads: [{1, 1}, {4, 4}, {16, 16}, {64, 32}],
      concurrencies: [1],
      endpoints: ["noop", "upload", "download", "echo"]
    )
  end

  defp build_scenarios(:tiny) do
    do_build_scenarios(
      protocols: ["http/1.1"],
      clients_and_threads: [{1, 1}, {4, 4}, {16, 16}],
      concurrencies: [1],
      endpoints: ["echo"]
    )
  end

  defp build_scenarios(huge) when huge in [:huge, :huge_bigfile] do
    do_build_scenarios(
      protocols: ["http/1.1", "h2c"],
      clients_and_threads: [{1, 1}, {4, 4}, {16, 16}, {64, 32}, {256, 32}, {1024, 32}],
      concurrencies: [1, 4, 16],
      endpoints: ["noop", "upload", "download", "echo"]
    )
  end

  defp do_build_scenarios(params) do
    for protocol <- params[:protocols],
        concurrency <- params[:concurrencies],
        {clients, threads} <- params[:clients_and_threads],
        endpoint <- params[:endpoints] do
      %{
        protocol: protocol,
        concurrency: concurrency,
        threads: threads,
        clients: clients,
        endpoint: endpoint
      }
    end
  end

  defp run_benchmark(scenario, server_def, profile) do
    duration =
      case {profile, scenario.clients} do
        {_, {clients, _}} when clients > 64 -> ["-n", "1000000"]
        {:tiny, _} -> ["-D", "5"]
        _ -> ["-D", "15", "--warm-up-time", "5"]
      end

    upload =
      if scenario.endpoint in [:upload, :echo] do
        if profile in [:normal_bigfile, :huge_bigfile],
          do: ["-d", @file_10m],
          else: ["-d", @file_10k]
      else
        []
      end

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
