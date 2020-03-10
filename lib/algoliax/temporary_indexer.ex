defmodule Algoliax.TemporaryIndexer do
  @moduledoc """
  Execute save_object(s) on temporary index to keep it synchronized with main index
  """

  import Algoliax.Utils, only: [index_name: 2]
  alias Algoliax.SettingsStore
  alias Algoliax.Resources.Object

  def run(action, module, settings, models, attributes, opts \\ []) do
    do_run(action, module, settings, models, attributes, opts)
  end

  defp do_run(action, module, settings, models, attributes, opts) do
    opts = Keyword.delete(opts, :temporary_only)

    index_name = index_name(module, settings)

    if SettingsStore.reindexing?(index_name) do
      tmp_index_name = :"#{index_name}.tmp"
      tmp_settings = SettingsStore.get_settings(tmp_index_name)

      execute(action, module, tmp_settings, models, attributes, opts)
    end
  end

  defp execute(:save_objects, module, settings, models, attributes, opts) do
    Object.save_objects(module, settings, models, attributes, opts)
  end

  defp execute(:save_object, module, settings, models, attributes, _) do
    Object.save_object(module, settings, models, attributes)
  end

  defp execute(:delete_object, module, settings, models, attributes, _) do
    Object.delete_object(module, settings, models, attributes)
  end
end
