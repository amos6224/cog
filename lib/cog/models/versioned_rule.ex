defmodule Cog.Models.VersionedRule do
 use Cog.Model
 alias Ecto.Changeset
 alias Cog.Models.CommandVersion
 alias Piper.Permissions.Ast
 alias Piper.Permissions.Parser

  schema "rules" do
    field :parse_tree, :string
    field :score, :integer
    field :enabled, :boolean, default: true

   belongs_to :command, CommandVersion

   has_many :permission_grants, Cog.Models.RulePermission
   has_many :permissions, through: [:permission_grants, :permission]

  end

  @required_fields ~w(parse_tree score)
  @optional_fields ~w(enabled)

  def insert_new(%CommandVersion{}=command, %Ast.Rule{}=rule) do
    insert_new(command, %{parse_tree: Parser.rule_to_json!(rule),
                          score: rule.score})
  end
  def insert_new(%CommandVersion{}=command, params) do
    command
    |> Ecto.Model.build(:rules, params)
    |> changeset(params)
    |> Repo.insert
  end

  def changeset(model, params) do
    model
    |> Changeset.cast(params, @required_fields, @optional_fields)
    |> unique_constraint(:no_dupes, name: "rules_command_id_parse_tree_index")
  end

end

defimpl Permittable, for: Cog.Models.VersionedRule do

  def grant_to(rule, permission),
    do: Cog.Models.JoinTable.associate(rule, permission)

  def revoke_from(_, _),
    do: raise "unimplemented"

end
