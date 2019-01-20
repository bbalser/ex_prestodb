defmodule Prestodb do

  defdelegate execute(statement), to: Prestodb.Statement
end
