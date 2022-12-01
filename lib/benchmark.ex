defmodule Benchmark do
  @moduledoc false

  def run(server, args) do
    server_def = parse!(server)

    Benchmark.Server.run(server_def, fn ->
      Benchmark.Client.run(server_def, args)
    end)
  end

  defp parse!(server) do
    case String.split(server, "@") do
      ["bandit", repo, treeish] -> %{server: "bandit", repo: repo, treeish: treeish}
      ["bandit"] -> %{server: "bandit", treeish: "local"}
      ["cowboy"] -> %{server: "cowboy", treeish: "master"}
      [server, treeish] -> %{server: server, treeish: treeish}
      other -> raise "Unsupported server definition #{inspect(other)}"
    end
    |> Map.merge(%{hostname: "localhost", port: 4000})
  end
end
