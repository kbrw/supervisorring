defmodule :dyn_child_handler do
  @moduledoc """
  Defines callback for dynamic children handler
  """

  @doc """
  TODO...
  """
  @callback get_all() :: any

  @doc """
  TODO...
  """
  @callback match(child_id::atom) :: any

  @doc """
  TODO...
  """
  @callback add(child_spec :: term) :: any

  @doc """
  TODO...
  """
  @callback del(child_id :: atom) :: any
end
