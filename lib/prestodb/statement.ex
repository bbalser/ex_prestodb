defmodule Prestodb.Statement do
  use Tesla

  defmodule Result do

    defstruct [:state, :next_uri, :columns, :data]

    def done?(result) do
      result.next_uri == nil
    end

    defimpl Enumerable, for: Result do
      def count(_result), do: {:error, __MODULE__}
      def member?(_result, _value), do: {:error, __MODULE__}
      def slice(_result), do: {:error, __MODULE__}

      def reduce(_result, {:halt, acc}, _fun), do: {:halted, acc}
      def reduce(result, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(result, &1, fun)}
      def reduce(%{data: []} = result, {:cont, acc}, fun) do
        case Result.done?(result) do
          true -> {:done, acc}
          false ->
            Prestodb.Statement.advance(result)
            |> reduce({:cont, acc}, fun)
        end
      end
      def reduce(%{columns: columns, data: [head|tail]} = result, {:cont, acc}, fun) do
        row = columns
        |> Enum.map(fn col -> col["name"] end)
        |> Enum.zip(head)
        |> Enum.into(%{})

        reduce(%{result | data: tail}, fun.(row, acc), fun)
      end

    end

  end

  plug(Tesla.Middleware.BaseUrl, Application.get_env(:prestodb, :base_url))
  plug(Tesla.Middleware.Headers, [{"X-Presto-User", "bbalser"}])
  plug(Tesla.Middleware.JSON)

  def execute(statement, opts \\ []) do
    query_opts = Enum.map(opts, fn {k, v} -> {"X-Presto-#{String.capitalize(to_string(k))}", v} end)
    post("/v1/statement", statement, headers: query_opts)
    |> transform()
  end

  def advance(%Result{next_uri: next_uri}) do
    get(next_uri)
    |> transform()
  end

  defp transform({:ok, %Tesla.Env{status: 200, body: body} = response}) do
    %Result{
      state: get_in(body, ["stats", "state"]),
      next_uri: body["nextUri"],
      columns: body["columns"] || [],
      data: body["data"] || []
    }
  end

  def get_all_results(%Result{next_uri: next_uri} = result) when not is_nil(next_uri)  do
    next_result = advance(result)
    %Result{ next_result | columns: Map.get(next_result, :columns, result.columns), data: result.data ++ next_result.data }
    |> get_all_results()
  end

  def get_all_results(%Result{} = result) do
    result
  end

end

