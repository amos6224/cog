defmodule Cog.Template.Engine do
  use EEx.Engine

  alias Cog.Template.Engine.Helpers
  alias Cog.Template.Engine.ForbiddenCallError

  @helper_functions Keyword.keys(Helpers.__info__(:functions))

  @whitelisted_kernel_forms [
    :., # Needed for nested assigns to work, if we keep with the
        # "template code has line numbers, generated code doesn't"
        # scheme
    :!=,
    :!==,
    :*,
    :++,
    :+,
    :-,
    :--,
    :/,
    :<,
    :<=,
    :==,
    :===,
    :=~,
    :>,
    :>=,
    :abs,
    :binary_part,
    :bit_size,
    :byte_size,
    :div,
    :hd,
    :is_binary,
    :is_bitstring,
    :is_boolean,
    :is_float,
    :is_integer,
    :is_list,
    :is_map,
    :is_number,
    :length,
    :map_size,
    :max,
    :min,
    :not,
    :rem,
    :round,
    :tl,
    :trunc,

    # Kernel macros
    :!,
    :..,
    :&&,
    :<>,
    :||,
    :and,
    :if,
    :in,
    :is_nil,
    :or,
    :sigil_r,
    :unless,

    # Kernel.SpecialForms
    :<<>>, # Needed to do ~r// style regexes
    :=,
    :case,
    :cond,
    :for,

    # Other stuff
    :<- # Need this in order to do for loops
  ]

  def handle_expr(buffer, marker, expr) do
    expr = expr
    |> Macro.prewalk(&handle_assign/1)  # Expand assigns access
    |> Macro.prewalk(&pass_whitelist/1) # Filter out illegal calls
    |> Macro.prewalk(&load_helpers/1)   # Wire up helpers
    super(buffer, marker, expr)
  end

  ########################################################################

  # Ensure that the functions defined in Cog.Template.Engine.Helpers
  # are available for invocation using the bare function name.
  #
  # That is, instead of doing this:
  #
  #     <%= Cog.Template.Engine.Helpers.join(@foo, ", ") %>
  #
  # template authors will do this:
  #
  #     <%= join(@foo, ", ") %>
  #
  # AST nodes for functions with different names than those in the
  # Helpers module pass through unmodified.
  def load_helpers({helper, meta, args}) when helper in @helper_functions do
    meta = meta
    |> Keyword.put(:context, Elixir)
    |> Keyword.put(:import, Helpers)

    {helper, meta, args}
  end
  def load_helpers(expr),
    do: expr

  # Raise an error for any function calls that are not bare calls.
  #
  # That is, Foo.Bar.baz("blah") is not allowed. In this way, we block
  # the vast majority of possible function calls.
  #
  # Calls to lower level Erlang functions are completely forbidden.
  def pass_whitelist({_, meta, _}=expr) do
    case Access.fetch(meta, :line) do
      # Code typed by the user in the template will have a line number
      # in the AST node metadata; code generated by EEx doesn't
      {:ok, _} -> do_pass_whitelist(expr)
      :error   -> expr
    end
  end
  def pass_whitelist(expr), do: expr

  def do_pass_whitelist({{:., _, [{:__aliases__, _, target}, fun]} , meta, fun_args}) do
    # Right now this blocks all Elixir code calls like
    # `Foo.Bar.baz(:blah)`. If we want to whitelist specific modules
    # or functions, we can do so with patterns like this:
    #
    #     {:., _, [{:__aliases__, _, [:Foo, :Bar]}, :baz]}
    #
    raise(ForbiddenCallError, target: target, fun: fun, arg_exprs: fun_args, line: meta[:line])
  end
  def do_pass_whitelist({{:., _, [erl_mod, erl_fun]}, meta, args})
    when is_atom(erl_mod) and is_atom(erl_fun),
      do: raise(ForbiddenCallError, target: erl_mod, fun: erl_fun, arg_exprs: args , line: meta[:line])

  # Can't call functions on a variable
  def do_pass_whitelist({{:., _, [{var, _, ctx}=t, fun]}, meta, args}) when is_atom(var) and is_atom(ctx) do
    raise(ForbiddenCallError, target: t, fun: fun, arg_exprs: args, line: meta[:line])
  end

  def do_pass_whitelist({fun, meta, args})
    when is_atom(fun)
    and not ((fun in @whitelisted_kernel_forms) or (fun in @helper_functions))
    and is_list(args) # prevents this catching variable AST nodes,
                      # where args is nil or an atom
  do
    raise(ForbiddenCallError, target: [:Kernel], fun: fun, arg_exprs: args, line: meta[:line])
  end
  def do_pass_whitelist(expr),
    do: expr

  # Same as EEx.Engine.handle_assign/1 but doesn't add a line
  # number. Right now, we're using line numbers as a way to
  # distinguish between template code and EEx-generated code.
  defp handle_assign({:@, _meta, [{name, _, atom}]}) when is_atom(name) and is_atom(atom) do
    quote do: EEx.Engine.fetch_assign!(var!(assigns), unquote(name))
  end
  defp handle_assign(arg),
    do: arg

end