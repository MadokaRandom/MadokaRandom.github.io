#!/usr/bin/env julia

using LinearAlgebra
using Plots
using Arpack
using Formatting
# plotly()

ngrid = 200
nlevel = 20
nelect = 17
max_iter = 1000
E_threshold = 1E-5

fn = zeros(nlevel)
fn[1:(nelect÷2)] .= 2
if 1 == nelect % 2
    fn[nelect÷2+1] = 1
end

x = collect(LinRange(-5, 5, ngrid))
Δx = x[2] - x[1]
∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (Δx^2)
V_empty = zeros(ngrid)
V_well = fill(1e10, ngrid); @. V_well[-2 <= x <= 2] = 0;
V_harm = x.^2

function get_density(fn::Vector{Float64}, ψ::Matrix{Float64}, Δx::Float64) ::Vector{Float64}
    # fn 是长度为 nlevel 的向量，表示电子的占据数函数
    # ψ 是一个 ngrid x nlevel 的矩阵

    # 首先来归一化波函数
    norms = sum(ψ.^2, dims=1) * Δx
    ψ ./= sqrt.(norms)

    # 求电子密度函数
    ρ = sum(ψ.^2 .* fn', dims=2)
    ρ = dropdims(ρ; dims=2)

    return ρ
end

function get_hartree(ρ::Vector{Float64}, x::Vector{Float64}; eps=1e-1) ::Tuple{Float64, Vector{Float64}}
    Δx = x[2] - x[1]
    energy = sum((ρ * ρ' .* Δx^2) ./ sqrt.((x' .- x).^2 .+ eps)) / 2
    potential = collect(Iterators.flatten((sum(ρ' .* Δx ./ sqrt.((x' .- x).^2 .+ eps), dims=2))))
    return (energy, potential)
end

function get_exchange(ρ::Vector{Float64}, Δx::Float64) ::Tuple{Float64, Vector{Float64}}
    energy = -3.0/4.0 * cbrt(3.0/π) * sum(ρ.^(4.0/3.0)) * Δx
    potential = -cbrt(3.0/π) .* (cbrt.(ρ))
    return (energy, potential)
end

function get_hamiltonian(x::Vector{Float64}, ρ::Vector{Float64},
                         v_ext::Vector{Float64}) ::Matrix{Float64}
    Δx = x[2] - x[1]
    ex_energy, ex_potential = get_exchange(ρ, Δx)
    ha_energy, ha_potential = get_hartree(ρ, x)
    ∇² = Tridiagonal(ones(ngrid-1), -2*ones(ngrid), ones(ngrid-1)) ./ (Δx^2)

    # Hamiltonian
    H = -∇²./2 + Diagonal(ex_potential .+ ha_potential .+ v_ext)

    return H
end

# potentials

p1 = plot(x, V_empty, label="V_empty")
p2 = plot(x, V_well, label="V_well")
p3 = plot(x, V_harm, label="V_harm")

p = plot(p1, p2, p3, layout=(3, 1), legend=true)
savefig(p, "potentials.svg")

# ψ and ρ

function get_E_ψ_ρ(V, Vname)
    E, ψ = eigs(-∇²/2 + Diagonal(V), nev=nlevel, which=:LM, sigma=0)
    ρ = get_density(fn, ψ, Δx)
    p = plot(x, ψ[:, 1:5], title="ψ_"*Vname, label=sprintf1.("%.3f", E[1:5]'), size=(800, 600))
    return (E, ψ, ρ, p)
end

E_empty, ψ_empty, ρ_empty, p_empty = get_E_ψ_ρ(V_empty, "empty")
E_well, ψ_well, ρ_well, p_well = get_E_ψ_ρ(V_well, "well")
E_harm, ψ_harm, ρ_harm, p_harm = get_E_ψ_ρ(V_harm, "harm")
p_ρ = plot(x, [ρ_empty, ρ_well, ρ_harm], label=["ρ_empty" "ρ_well" "ρ_harm"], title="Electronic Density ρ", size=(800, 600))
p = plot(p_empty, p_well, p_harm, p_ρ, layout=(2, 2), legend=true)
savefig(p, "psi_rho.svg")
