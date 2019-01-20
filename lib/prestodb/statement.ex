defmodule Prestodb.Statement do
  use Tesla

  defmodule Result do
    defstruct [:state, :next_uri, :columns, :data, :by_names]

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
          true ->
            {:done, acc}

          false ->
            Prestodb.Statement.advance(result)
            |> reduce({:cont, acc}, fun)
        end
      end

      def reduce(%{data: [head | tail]} = result, {:cont, acc}, fun) do
        row = transform_row(head, result.columns, result.by_names)
        reduce(%{result | data: tail}, fun.(row, acc), fun)
      end

      defp transform_row(row, _columns, false), do: row

      defp transform_row(row, columns, true) do
        columns
        |> Enum.map(fn col -> col["name"] end)
        |> Enum.zip(row)
        |> Enum.into(%{})
      end
    end
  end

  plug(Tesla.Middleware.BaseUrl, Application.get_env(:prestodb, :base_url))
  plug(Tesla.Middleware.Headers, [{"X-Presto-User", "bbalser"}])
  plug(Tesla.Middleware.JSON)

  def execute(statement, opts \\ []) do
    {by_names, header_opts} = Keyword.get_and_update(opts, :by_names, fn _ -> :pop end)

    headers =
      Enum.map(header_opts, fn {k, v} -> {"X-Presto-#{String.capitalize(to_string(k))}", v} end)

    post("/v1/statement", statement, headers: headers)
    |> transform(%Result{by_names: by_names || false})
  end

  def advance(%Result{next_uri: next_uri} = result) do
    get(next_uri)
    |> transform(result)
  end

  defp transform({:ok, %Tesla.Env{status: 200, body: body}}, %Result{by_names: by_names}) do
    %Result{
      state: get_in(body, ["stats", "state"]),
      next_uri: body["nextUri"],
      columns: body["columns"] || [],
      data: body["data"] || [],
      by_names: by_names
    }
  end

  def get_all_results(%Result{next_uri: next_uri} = result) when not is_nil(next_uri) do
    next_result = advance(result)

    %Result{
      next_result
      | columns: Map.get(next_result, :columns, result.columns),
        data: result.data ++ next_result.data
    }
    |> get_all_results()
  end

  def get_all_results(%Result{} = result) do
    result
  end
end
