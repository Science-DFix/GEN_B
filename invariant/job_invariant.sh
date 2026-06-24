#!/bin/bash
#PBS -S /bin/bash
#PBS -q pesqmidi
#PBS -l select=1:ncpus=128
#PBS -l walltime=02:00:00
#PBS -N MPAS-Invariant
#PBS -j oe
#PBS -o MPAS-Invariant.out

# ==============================================================================
# Gera x1.163842.invariant.nc com precisão SIMPLES
# Executável: build_mpas_sp (compilado com -DMPAS_DOUBLE_PRECISION=OFF)
# ==============================================================================

DIR_BUILD="/lustre/projetos/satdas/diego_workdir/TESTE_MPAS_JEDI/build_mpas_sp"
DIR_WORK="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant"

source /lustre/projetos/satdas/opt/spack/linux-sles15-zen4/gcc-13.3.0/lmod-8.7.37-6uohtfnul3kvi74dn5y2gj4dkj2hd77p/lmod/lmod/init/bash
source /lustre/projetos/satdas/diego_workdir/spack_env_for_mpas_bundle/gcc13.3-openmpi.sh

cd "${DIR_WORK}" || exit 1

# Linka executável de precisão simples
ln -sf "${DIR_BUILD}/bin/mpas_init_atmosphere" ./mpas_init_atmosphere

# Linka tabelas de física do build correto
ln -sf "${DIR_BUILD}/_deps/mpas_data-src/atmosphere/physics_wrf/files/"* ./

ulimit -s unlimited

echo "Iniciando geracao do Invariant (precisão simples) em: $(date)"
echo "Diretorio: $(pwd)"
echo "Executável: $(readlink mpas_init_atmosphere)"
echo "Verificando namelist:"
grep -E "config_static_interp|config_native_gwd_static|config_vertical_grid|config_met_interp" namelist.init_atmosphere

mpirun -np 128 ./mpas_init_atmosphere

echo "Finalizado em: $(date)"

if [ -f "x1.163842.invariant.nc" ]; then
    echo "SUCESSO — tamanho: $(du -sh x1.163842.invariant.nc | cut -f1)"
    # Verifica precisão do arquivo gerado
    ncdump -h x1.163842.invariant.nc | grep "^\s\+float\|^\s\+double" | head -5
else
    echo "ERRO — x1.163842.invariant.nc nao foi gerado"
    exit 1
fi
