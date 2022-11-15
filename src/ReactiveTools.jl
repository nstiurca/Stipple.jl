module ReactiveTools

using Stipple
using MacroTools
using MacroTools: postwalk
using OrderedCollections
import Genie

export @binding, @readonly, @private, @in, @out, @value, @jsfn, @mix_in
export @page, @rstruct, @type, @handlers, @init, @model, @onchange, @onchangeany, @onbutton
export DEFAULT_LAYOUT, Page

const REACTIVE_STORAGE = LittleDict{Module,LittleDict{Symbol,Expr}}()
const TYPES = LittleDict{Module,Union{<:DataType,Nothing}}()

function DEFAULT_LAYOUT(; title::String = "Genie App")
  """
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <% Stipple.sesstoken() %>
    <title>$title</title>
    <% if isfile(joinpath(Genie.config.server_document_root, "css", "genieapp.css")) %>
    <link rel='stylesheet' href='/css/genieapp.css'>
    <% else %>
    <% end %>
    <% if isfile(joinpath(Genie.config.server_document_root, "css", "autogenerated.css")) %>
    <link rel='stylesheet' href='/css/autogenerated.css'>
    <% else %>
    <% end %>
    <style>
      ._genie_logo {
        background:url('/stipple.jl/master/assets/img/genie-logo.img') no-repeat;background-size:40px;
        padding-top:22px;padding-right:10px;color:transparent;font-size:9pt;
      ._genie .row .col-12 { width:50%;margin:auto; }
      }
    </style>
  </head>
  <body>
    <div class='container'>
      <div class='row'>
        <div class='col-12'>
          <% page(model, partial = true, v__cloak = true, [@yield], @iif(:isready)) %>
        </div>
      </div>
    </div>
    <% if isfile(joinpath(Genie.config.server_document_root, "js", "genieapp.js")) %>
    <script src='/js/genieapp.js'></script>
    <% else %>
    <% end %>
    <footer class='_genie container'>
      <div class='row'>
        <div class='col-12'>
          <p class='text-muted credit' style='text-align:center;color:#8d99ae;'>Built with
            <a href='https://genieframework.com' target='_blank' class='_genie_logo' ref='nofollow'>Genie</a>
          </p>
        </div>
      </div>
    </footer>
  </body>
</html>
"""
end

function default_struct_name(m::Module)
  "$(m)_ReactiveModel"
end

function init_storage(m::Module)
  (m == @__MODULE__) && return nothing

  haskey(REACTIVE_STORAGE, m) || (REACTIVE_STORAGE[m] = LittleDict{Symbol,Expr}())
  haskey(TYPES, m) || (TYPES[m] = nothing)

end

#===#

function clear_type(m::Module)
  TYPES[m] = nothing
end

function delete_bindings!(m::Module)
  clear_type(m)
  delete!(REACTIVE_STORAGE, m)
end

function bindings(m)
  init_storage(m)
  REACTIVE_STORAGE[m]
end

#===#

macro rstruct()
  init_storage(__module__)
  modelname = Symbol(default_struct_name(__module__))
  output = Core.eval(__module__, :(
    values(ReactiveTools.REACTIVE_STORAGE[@__MODULE__])
  ))
    
  esc(quote
    @type $modelname begin
      $(output...)
    end
  end)  
end

import Stipple.@type

macro type()
  init_storage(__module__)
  esc(quote
    if Stipple.ReactiveTools.TYPES[@__MODULE__] !== nothing
      ReactiveTools.TYPES[@__MODULE__]
    else
      ReactiveTools.TYPES[@__MODULE__] = ReactiveTools.@rstruct()
    end
  end)
end

macro model()
  init_storage(__module__)

  esc(quote
    @type() |> Base.invokelatest
  end)
end

#===#

function find_assignment(expr)
  assignment = nothing

  if isa(expr, Expr) && !contains(string(expr.head), "=")
    for arg in expr.args
      assignment = if isa(arg, Expr)
        find_assignment(arg)
      end
    end
  elseif isa(expr, Expr) && contains(string(expr.head), "=")
    assignment = expr
  else
    assignment = nothing
  end

  assignment
end

function parse_expression(expr::Expr, @nospecialize(mode) = nothing, source = nothing)
  expr = find_assignment(expr)

  (isa(expr, Expr) && contains(string(expr.head), "=")) ||
    error("Invalid binding expression -- use it with variables assignment ex `@binding a = 2`")

  source = (source !== nothing ? "\"$(strip(replace(replace(string(source), "#="=>""), "=#"=>"")))\"" : "")
  if Sys.iswindows()
    source = replace(source, "\\"=>"\\\\")
  end

  var = expr.args[1]
  if !isnothing(mode)
    type = if isa(var, Expr) && var.head == Symbol("::")
      # change type R to type R{T}
      var.args[2] = :(R{$(var.args[2])})
    else
      # add type definition `::R` to the var and return type `R`
      expr.args[1] = :($var::R)
      :R
    end
    expr.args[2] = :($type($(expr.args[2]), $mode, false, false, source))
  end

  expr.args[1].args[1], expr
end

function binding(expr::Symbol, m::Module, @nospecialize(mode::Any = nothing); source = nothing)
  binding(:($expr = $expr), m, mode; source)
end

function binding(expr::Expr, m::Module, @nospecialize(mode::Any = nothing); source = nothing)
  (m == @__MODULE__) && return nothing

  init_storage(m)

  var, field_expr = parse_expression(expr, mode, source)
  REACTIVE_STORAGE[m][var] = field_expr

  # remove cached type and instance
  clear_type(m)

  instance = @eval m @type()
  for p in Stipple.Pages._pages
    p.context == m && (p.model = instance)
  end
end

macro reportval(expr)
  val = expr isa Symbol ? expr : expr.args[2]
  issymbol = val isa Symbol
  esc(quote
    $issymbol ? (isdefined(@__MODULE__, $(QuoteNode(val))) ? $val : @info(string("Warning: Variable '", $(QuoteNode(val)), "' not yet defined"))) : Stipple.Observables.to_value($val)
  end)
end

# works with
# @in a = 2
# @in a::Vector = [1, 2, 3]
# @in a::Vector{Int} = [1, 2, 3]
macro in(expr)
  binding(expr, __module__, :PUBLIC; source = __source__)
  esc(:(ReactiveTools.@reportval($expr)))
end

macro out(expr)
  binding(expr, __module__, :READONLY; source = __source__)
  esc(:(ReactiveTools.@reportval($expr)))
end

macro readonly(expr)
  esc(:(@out($expr)))
end

macro private(expr)
  binding(expr, __module__, :PRIVATE; source = __source__)
  esc(:(ReactiveTools.@reportval($expr)))
end

macro jsfn(expr)
  binding(expr, __module__, :JSFUNCTION; source = __source__)
  esc(:(ReactiveTools.@reportval($expr)))
end

macro mix_in(expr, prefix = "", postfix = "")
  init_storage(__module__)

  if hasproperty(expr, :head) && expr.head == :(::)
      prefix = string(expr.args[1])
      expr = expr.args[2]
  end

  x = Core.eval(__module__, expr)
  pre = Core.eval(__module__, prefix)
  post = Core.eval(__module__, postfix)

  T = x isa DataType ? x : typeof(x)
  mix = x isa DataType ? x() : x
  values = getfield.(Ref(mix), fieldnames(T))
  ff = Symbol.(pre, fieldnames(T), post)
  for (f, type, v) in zip(ff, fieldtypes(T), values)
      v_copy = Stipple._deepcopy(v)
      expr = :($f::$type = Stipple._deepcopy(v))
      REACTIVE_STORAGE[__module__][f] = v isa Symbol ? :($f::$type = $(QuoteNode(v))) : :($f::$type = $v_copy)
  end

  clear_type(__module__)
  instance = @eval __module__ @type()
  for p in Stipple.Pages._pages
    p.context == __module__ && (p.model = instance)
  end
  esc(Stipple.Observables.to_value.(values))
end

#===#

macro init(modeltype)
  quote
    local initfn =  if isdefined($__module__, :init_from_storage)
                      $__module__.init_from_storage
                    else
                      $__module__.init
                    end
    local handlersfn =  if isdefined($__module__, :__GF_AUTO_HANDLERS__)
                          $__module__.__GF_AUTO_HANDLERS__
                        else
                          identity
                        end

    instance = $modeltype |> initfn |> handlersfn
    for p in Stipple.Pages._pages
      p.context == $__module__ && (p.model = instance)
    end
    instance
  end |> esc
end

macro init()
  quote
    @init(@type())
  end |> esc
end

macro handlers(expr)
  quote
    isdefined(@__MODULE__, :__HANDLERS__) || @eval const __HANDLERS__ = Stipple.Observables.ObserverFunction[]

    function __GF_AUTO_HANDLERS__(__model__)
      empty!(__HANDLERS__)

      $expr

      return __model__
    end
  end |> esc
end

macro process_handler_input()
  quote
    known_vars = push!(Stipple.ReactiveTools.REACTIVE_STORAGE[__module__] |> keys |> collect, :isready, :isprocessing) # add mixins

    if isa(var, Symbol) && in(var, known_vars)
      var = :(__model__.$var)
    else
      error("Unknown binding $var")
    end

    expr = postwalk(x -> isa(x, Symbol) && in(x, known_vars) ? :(__model__.$x[]) : x, expr)
  end |> esc
end

macro onchange(var, expr)
  @process_handler_input()

  quote
    push!(__HANDLERS__, (
      on($var) do __value__
        $expr
      end
      )
    )
  end |> esc
end

macro onchangeany(vars, expr)
  known_vars = push!(Stipple.ReactiveTools.REACTIVE_STORAGE[__module__] |> keys |> collect, :isready, :isprocessing) # add mixins

  va = postwalk(x -> isa(x, Symbol) && in(x, known_vars) ? :(__model__.$x) : x, vars)
  exp = postwalk(x -> isa(x, Symbol) && in(x, known_vars) ? :(__model__.$x[]) : x, expr)

  quote
    push!(__HANDLERS__, (
      onany($va...) do (__values__...)
        $exp
      end
      )...
    )
  end |> esc
end

macro onbutton(var, expr)
  @process_handler_input()

  quote
    push!(__HANDLERS__, (
      onbutton($var) do __value__
        $expr
      end
      )
    )
  end |> esc
end

#===#

macro page(url, view, layout, model, context)
  quote
    Stipple.Pages.Page( $url;
                        view = $view,
                        layout = $layout,
                        model = $model,
                        context = $context)
  end |> esc
end

macro page(url, view, layout, model)
  :(@page($url, $view, $layout, () -> @init, $__module__)) |> esc
end

macro page(url, view, layout)
  :(@page($url, $view, $layout, () -> @init)) |> esc
end

macro page(url, view)
  :(@page($url, $view, Stipple.ReactiveTools.DEFAULT_LAYOUT())) |> esc
end



end