defmodule Cog.V1.PermissionControllerTest do
  use Cog.ConnCase
  use Cog.ModelCase

  alias Cog.Models.Permission

  @bad_uuid "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

  setup do
    namespace("site")
    required_permission = permission("#{Cog.embedded_bundle}:manage_permissions")

    # This user will be used to test the normal operation of the controller
    authed_user = user("cog")
    |> with_token
    |> with_permission(required_permission)

    # This user will be used to verify that the above permission is
    # indeed required for requests
    unauthed_user = user("sadpanda") |> with_token

    # Role to use for permission grant/revoke tests
    role = role("test-role")
    |> with_permission(required_permission)

    {:ok, [user: authed_user, unauthed: unauthed_user, role: role]}
  end

  test "lists all entries on index", %{user: user} do
    conn = api_request(user, :get, "/v1/permissions")
    permissions_list = json_response(conn, 200)["permissions"]

    names = permissions_list
    |> Enum.map(&Map.get(&1, "name"))
    |> Enum.sort

    # Everything currently in the embedded bundle, which is present on
    # system startup
    assert names == ["manage_commands",
                     "manage_groups", "manage_permissions", "manage_relays",
                     "manage_roles", "manage_users", "st-echo",
                     "st-thorn"]
  end

  test "lists permissions granted to role", %{user: user, role: role} do
    :ok = Permittable.grant_to(role, permission("operable:manage_commands"))

    conn = api_request(user, :get, "/v1/roles/#{role.id}/permissions")
    permissions_list = json_response(conn, 200)["permissions"]

    names = permissions_list
    |> Enum.map(&Map.get(&1, "name"))
    |> Enum.sort

    assert names == ["manage_commands", "manage_permissions"]
  end

  test "creates and renders resource when data is valid", %{user: user} do
    conn = api_request(user, :post, "/v1/permissions",
                       body: %{"permission" => %{name: "test_perm"}})
    recv_perm = json_response(conn, 201)["permission"]
    assert recv_perm["name"] == "test_perm"
    assert recv_perm["id"] != nil
    assert Repo.get(Permission, recv_perm["id"])
  end

  test "does not create resource and renders errors when attempting to create an existing permission", %{user: user} do
    existing_perm = permission("site:existing_perm")
    conn = api_request(user, :post, "/v1/permissions",
                       body: %{"permission" => %{"name" => existing_perm.name}})
    assert json_response(conn, 422)["errors"] == %{"name" => ["has already been taken"]}
  end

  test "shows chosen resource regardless of namespace", %{user: user} do
    # random namespace
    rand_perm = permission("joe:test_perm") |> Repo.preload(:namespace)
    conn = api_request(user, :get, "/v1/permissions/#{rand_perm.id}")
    assert json_response(conn, 200) == %{
      "permission" =>
        %{"namespace" => rand_perm.namespace.name,
          "id" => rand_perm.id,
          "name" => rand_perm.name}
      }

    # site namespace
    site_perm = permission("site:test_perm") |> Repo.preload(:namespace)
    conn = api_request(user, :get, "/v1/permissions/#{site_perm.id}")
    assert json_response(conn, 200) == %{
      "permission" =>
        %{"namespace" => site_perm.namespace.name,
          "id" => site_perm.id,
          "name" => site_perm.name}
      }


    # embedded bundle namespace
    embedded_perm = permission("#{Cog.embedded_bundle}:test_perm") |> Repo.preload(:namespace)
    conn = api_request(user, :get, "/v1/permissions/#{embedded_perm.id}")
    assert json_response(conn, 200) == %{
      "permission" =>
        %{"namespace" => embedded_perm.namespace.name,
          "id" => embedded_perm.id,
          "name" => embedded_perm.name}
      }

  end

  test "does not show resource and instead throw error when id is nonexistent", %{user: user} do
    assert_raise Ecto.NoResultsError, fn ->
      api_request(user, :get, "/v1/permissions/#{@bad_uuid}")
    end
  end

  test "cannot update a permission", %{user: user} do
    permission = permission("site:tester")
    conn = api_request(user, :put, "/v1/permissions/#{permission.id}",
                       body: %{"permission" => %{"name" => "other_perm"}})

    json_response(conn, 404)

    # Permission retains it's name
    assert Repo.get!(Permission, permission.id).name == "tester"
  end

  test "deletes chosen resource", %{user: user} do
    permission = permission("site:tester")
    conn = api_request(user, :delete, "/v1/permissions/#{permission.id}")
    assert response(conn, 204)
    refute Repo.get(Permission, permission.id)
  end

  test "fails when attempting to delete non-site resource", %{user: user} do
    permission = permission("robert:tester")
    conn = api_request(user, :delete, "/v1/permissions/#{permission.id}")
    assert response(conn, 403)
  end

  test "fails when attempting to delete embedded bundle permission", %{user: user} do
    conn = api_request(user, :get, "/v1/permissions")
    [first | _remaining] = json_response(conn, 200)["permissions"]
    conn = api_request(user, :delete, "/v1/permissions/#{first["id"]}")
    assert response(conn, 403)
  end

  test "cannot create permissions without permission", %{unauthed: user} do
    conn = api_request(user, :post, "/v1/permissions",
                       body: %{"permission" => %{"name" => "new_perm"}})
    assert conn.halted
    assert conn.status == 403
  end

  test "cannot delete a permissions without permission", %{unauthed: user} do
    permission = permission("site:alien_perm")
    conn = api_request(user, :delete, "/v1/permissions/#{permission.id}")
    assert conn.halted
    assert conn.status == 403
  end

end
