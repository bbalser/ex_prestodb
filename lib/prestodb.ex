defmodule Prestodb do
  defdelegate execute(statement, opts \\ []), to: Prestodb.Statement
end
