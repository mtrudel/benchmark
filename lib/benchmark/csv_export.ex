defmodule Benchmark.CSVExport do
  @moduledoc false

  @headers [
    server: "Server",
    treeish: "Treeish",
    protocol: "Protocol",
    clients: "Number of clients",
    concurrency: "Client concurrency",
    threads: "Number of client threads",
    status_2xx: "Number of 2xx responses",
    status_3xx: "Number of 3xx responses",
    status_4xx: "Number of 4xx responses",
    status_5xx: "Number of 5xx responses",
    reqs_per_sec_max: "Requests per second (max)",
    reqs_per_sec_mean: "Requests per second (mean)",
    reqs_per_sec_min: "Requests per second (min)",
    reqs_per_sec_sd: "Requests per second (stddev)",
    time_to_connect_max: "Time to connect (max)",
    time_to_connect_mean: "Time to connect (mean)",
    time_to_connect_min: "Time to connect (min)",
    time_to_connect_sd: "Time to connect (stddev)",
    time_to_first_byte_max: "Time to first byte (max)",
    time_to_first_byte_mean: "Time to first byte (mean)",
    time_to_first_byte_min: "Time to first byte (min)",
    time_to_first_byte_sd: "Time to first byte (stddev)",
    time_to_request_max: "Time to request (max)",
    time_to_request_mean: "Time to request (mean)",
    time_to_request_min: "Time to request (min)",
    time_to_request_sd: "Time to request (stddev)",
    memory_atom: "Atom memory",
    memory_binary: "Binary memory",
    memory_code: "Code memory",
    memory_ets: "ETS memory",
    memory_processes: "Process memory",
    memory_system: "System memory",
    memory_total: "Total memory"
  ]

  def export(results, filename) do
    File.open!(filename, [:write, :utf8], fn file ->
      results
      |> Enum.map(fn result ->
        result.result
        |> Map.merge(result.scenario)
        |> Map.merge(result.server_def)
      end)
      |> CSV.encode(headers: @headers)
      |> Enum.each(&IO.write(file, &1))
    end)
  end
end
