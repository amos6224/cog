defmodule Cog.Models.Bundle do
  use Cog.Model
  use Cog.Models

  schema "bundles" do
    field :name, :string
    field :version, Cog.Models.Bundle.Version, default: [0,0,0]
    field :config_file, :map
    field :manifest_file, :map
    field :enabled, :boolean, default: false

    has_many :commands, Command
    has_many :templates, Template
    has_one :namespace, Namespace

    timestamps
  end

  @required_fields ~w(name config_file manifest_file)
  @optional_fields ~w(enabled version)

  summary_fields [:id, :name, :version, :namespace, :inserted_at, :enabled]
  detail_fields [:id, :name, :version, :namespace, :commands, :inserted_at, :enabled]

  def changeset(model, params \\ :empty) do
    model
    |> cast(params, @required_fields, @optional_fields)
    |> validate_format(:name, ~r/\A[A-Za-z0-9\_\-\.]+\z/)
    |> unique_constraint(:name, name: :bundles_name_version_index)
    |> enable_if_embedded
  end

  def embedded?(%__MODULE__{name: name}),
    do: name == Cog.embedded_bundle
  def embedded?(_),
    do: false

  # When the embedded bundle is installed, it should always be
  # enabled. Though we prevent disabling it elsewhere, this code also
  # happens to block that, as well.
  #
  # Nothing is changed if it is not the embedded bundle.
  defp enable_if_embedded(changeset) do
    embedded = Cog.embedded_bundle
    case fetch_field(changeset, :name) do
      {_, ^embedded} ->
        put_change(changeset, :enabled, true)
      _ ->
        changeset
    end
  end

  def bundle_path(%__MODULE__{name: name}) do
    Path.join(bundle_root!, name)
  end

  def bundle_ebin_path(bundle) do
    Path.join(bundle_path(bundle), "ebin")
  end

  def bundle_root! do
    Application.get_env(:cog, Cog.Bundle.BundleSup)
    |> Keyword.fetch!(:bundle_root)
  end

  def bundle_root do
    Application.get_env(:cog, Cog.Bundle.BundleSup)
    |> Keyword.get(:bundle_root, nil)
  end
end
