defmodule Prestodb do
  defdelegate execute(statement, opts \\ []), to: Prestodb.Statement

  defdelegate prefetch(result), to: Prestodb.Statement
end
