defmodule Benchmark do
  @moduledoc false

  def run(server, profile) do
    server_def = parse!(server)

    Benchmark.Server.run(server_def, fn ->
      Benchmark.Client.run(server_def, profile)
    end)
  end

  defp parse!(server) do
    case String.split(server, "@") do
      [server, treeish] -> %{server: server, treeish: treeish}
      ["bandit"] -> %{server: "bandit", treeish: "local"}
      ["cowboy"] -> %{server: "cowboy", treeish: "master"}
      other -> raise "Unsupported server definition #{other}"
    end
    |> Map.merge(%{hostname: "localhost", port: 4000})
  end
end
