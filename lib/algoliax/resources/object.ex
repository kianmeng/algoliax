defmodule Algoliax.Resources.Object do
  @moduledoc false

  alias Algoliax.{Requests, SettingsStore, TemporaryIndexer, Utils}
  alias Algoliax.Resources.Index

  import Ecto.Query

  def get_object(module, settings, model, attributes) do
    Index.ensure_settings(module, settings)

    object_id = get_object_id(module, settings, model, attributes)
    Requests.get_object(Utils.index_name(module, settings), %{objectID: object_id})
  end

  def save_objects(module, settings, models, attributes, opts) do
    Index.ensure_settings(module, settings)

    index_name = Utils.index_name(module, settings)

    objects =
      Enum.map(models, fn model ->
        action = get_action(module, model, opts)

        if action do
          build_batch_object(module, settings, model, attributes, action)
        end
      end)
      |> Enum.reject(&is_nil/1)

    response = Requests.save_objects(index_name, %{requests: objects})
    call_indexer(:save_objects, module, settings, models, attributes, opts)
    response
  end

  def save_object(module, settings, model, attributes) do
    Index.ensure_settings(module, settings)

    if apply(module, :to_be_indexed?, [model]) do
      object = build_object(module, settings, model, attributes)
      index_name = Utils.index_name(module, settings)
      response = Requests.save_object(index_name, object)
      call_indexer(:save_object, module, settings, model, attributes)
      response
    else
      {:not_indexable, model}
    end
  end

  def delete_object(module, settings, model, attributes) do
    Index.ensure_settings(module, settings)
    call_indexer(:delete_object, module, settings, model, attributes)
    object = build_object(module, settings, model, attributes)
    index_name = Utils.index_name(module, settings)
    Requests.delete_object(index_name, object)
  end

  def reindex(module, settings, index_attributes, query, opts \\ []) do
    Index.ensure_settings(module, settings)

    repo = Utils.repo(settings)

    query =
      case query do
        %Ecto.Query{} = query ->
          query

        _ ->
          from(m in module)
      end

    Utils.find_in_batches(repo, query, 0, settings, fn batch ->
      save_objects(module, settings, batch, index_attributes, opts)
    end)
  end

  def reindex_atomic(module, settings, index_attributes) do
    Utils.repo(settings)

    Index.ensure_settings(module, settings)

    index_name = Utils.index_name(module, settings)
    tmp_index_name = :"#{index_name}.tmp"
    tmp_settings = Keyword.put(settings, :index_name, tmp_index_name)

    Index.ensure_settings(module, tmp_settings)
    SettingsStore.start_reindexing(index_name)

    reindex(module, tmp_settings, index_attributes, nil)

    response =
      Requests.move_index(tmp_index_name, %{
        operation: "move",
        destination: "#{index_name}"
      })

    Algoliax.SettingsStore.delete_settings(tmp_index_name)
    Algoliax.SettingsStore.stop_reindexing(index_name)

    response
  end

  defp build_batch_object(module, settings, model, attributes, action) do
    %{
      action: action,
      body: build_object(module, settings, model, attributes)
    }
  end

  defp build_object(module, settings, model, attributes) do
    Enum.into(attributes, %{}, fn a ->
      {Utils.unprefix_attribute(a), apply(module, a, [model])}
    end)
    |> prepare_object(model, settings)
    |> Map.put(:objectID, get_object_id(module, settings, model, attributes))
  end

  defp prepare_object(object, model, settings) do
    do_prepare_object(object, model, Keyword.get(settings, :prepare_object))
  end

  defp do_prepare_object(object, model, prepare_object_fn)
       when is_function(prepare_object_fn, 2) do
    prepare_object_fn.(object, model)
  end

  defp do_prepare_object(object, _, _) do
    object
  end

  defp get_object_id(module, settings, model, attributes) do
    object_id_attribute = Keyword.get(settings, :object_id)

    case Enum.find(attributes, fn a -> a == Utils.prefix_attribute(object_id_attribute) end) do
      nil ->
        Map.get(model, object_id_attribute)

      a ->
        apply(module, a, [model])
    end
  end

  defp get_action(module, model, opts) do
    if apply(module, :to_be_indexed?, [model]) do
      "updateObject"
    else
      if Keyword.get(opts, :force_delete) do
        "deleteObject"
      end
    end
  end

  defp call_indexer(action, module, settings, models, attributes, opts \\ []) do
    TemporaryIndexer.run(action, module, settings, models, attributes, opts)
  end
end
