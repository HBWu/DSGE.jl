using Distributions: Distribution
import Base: convert, promote_rule, log, exp

using DSGE.DistributionsExt: PointMass

# We define Param to be a subtype of Number so that we can use numerical operation methods in
#   https://github.com/JuliaLang/julia/blob/master/base/promotion.jl

# Some parameter values, especially rates, are given in one form but in practice we would like to
# use them in another form. For example, pistar = 0.5000 refers to an inflation rate of 0.5%; its
# scalefunction x -> 1 + x/100 specifies the form in which pistar is used in calculations. We
# use the scaled parameter value in calculations, but the original value in estimation.

type Param <: Number
    value::Float64
    scalefunction::Function
    scaledvalue::Float64
    fixed::Bool
    bounds::(Float64, Float64)
    prior::Distribution
    transformtype::Int64
    transformbounds::(Float64, Float64)
    description::String

    function Param(value::Float64, fixed::Bool, bounds::(Float64, Float64), prior::Distribution,
                   transformtype::Int64, transformbounds::(Float64, Float64);
                   scalefunction::Function = identity, description::String = "")
        if fixed
            prior = PointMass(value)
            transformtype = 0
            transformbounds = (value, value)
        end
        if transformtype != 0 && transformtype != 1 && transformtype != 2
            error("transformtype must be 0, 1, or 2")
        end
        (a, b) = transformbounds
        return new(value, scalefunction, scalefunction(value), fixed, bounds, prior, transformtype,
                   transformbounds, description)
    end
end

# Constructor for values given in getpara00_990.m as del = 0.025, for example
function Param(value::Float64)
    return Param(value, true, (value, value), PointMass(value), 0, (value, value))
end



# Methods so that arithmetic with parameters can be done tersely, like "θ.α + θ.β"
# Note there are still instances where we must refer to α.scaledvalue, e.g. pdf(α.prior, α.val)
Base.convert{T<:FloatingPoint}(::Type{T}, α::Param) = α.scaledvalue
Base.promote_rule{T<:FloatingPoint}(::Type{Param}, ::Type{T}) = Float64
Base.promote_rule{T<:Integer}(::Type{Param}, ::Type{T}) = Float64

for op in [:+, :-, :*, :/, :^]
    @eval ($op)(α::Param, β::Param) = ($op)(α.scaledvalue, β.scaledvalue)
end

for f in [:-, :log, :exp]
    @eval ($f)(α::Param) = $(f)(α.scaledvalue)
end

# Transforms variables from model to max (invtrans.m)
function toreal(α::Param)
    (a, b) = α.transformbounds
    c = 1.

    if α.transformtype == 0
       return α.scaledvalue
    elseif α.transformtype == 1
        cx = 2 * (α - (a+b)/2) / (b-a)
        return (1/c) * cx / sqrt(1 - cx^2)
    elseif α.transformtype == 2
        return b + (1/c) * log(α-a)
    end
end

# Transforms variables from max to model (trans.m)
function tomodel(α::Param)
    (a, b) = α.transformbounds
    c = 1.

    if α.transformtype == 0
        return α.scaledvalue
    elseif α.transformtype == 1
        return (a+b)/2 + (b-a)/2*c*α/sqrt(1 + c^2 * α.scaledvalue^2)
    elseif α.transformtype == 2
        return a + exp(c * (α-b))
    end
end