# invariant — Geração do Arquivo de Coordenada Vertical do MPAS-A

## O que é o invariant?

O arquivo `x1.163842.invariant.nc` contém a **grade vertical híbrida sigma-pressão** do MPAS-A. Ele é chamado de "invariante" porque **não depende de data, hora ou condições meteorológicas** — é fixo para uma dada configuração de malha e grade vertical.

Este arquivo é gerado **uma única vez** por configuração de malha e reutilizado em todas as rodadas do modelo.

---

## Arquivos do diretório

| Arquivo | Descrição |
|---------|-----------|
| `job_invariant.sh` | Script PBS para submissão no cluster Jaci |
| `namelist.init_atmosphere` | Configuração do `init_atmosphere_model` para gerar o invariant |
| `streams.init_atmosphere` | Define entrada (`static.nc`) e saída (`invariant.nc`) |
| `log.init_atmosphere.0000.out` | Exemplo de log de execução bem-sucedida |

---

## Como funciona

O invariant é gerado pelo executável `init_atmosphere_model` com `config_init_case = 7`, que ativa **apenas** a etapa de construção da grade vertical (`config_vertical_grid = true`), sem processar dados meteorológicos.

```
x1.163842.static.nc   ←── malha horizontal (entrada)
        │
        ▼
  init_atmosphere_model
  (config_init_case = 7)
        │
        ▼
x1.163842.invariant.nc  ←── grade vertical + coordenadas (saída)
```

### Importante: precisão simples obrigatória

O invariant **deve ser gerado com o build de precisão simples** (`build_mpas_sp`), mesmo que as rodadas de previsão usem precisão dupla. Isso é exigência do MPAS-JEDI para leitura correta do arquivo.

---

## Configuração do `namelist.init_atmosphere`

```fortran
&nhyd_model
    config_init_case  = 7                    ! Modo: geração de grade vertical
    config_start_time = '2026-01-01_00:00:00' ! Qualquer data (não afeta o resultado)
    config_stop_time  = '2026-01-01_00:00:00'
/
&dimensions
    config_nvertlevels   = 55   ! Número de níveis verticais atmosféricos
    config_nsoillevels   = 4    ! Níveis de solo
    config_nfglevels     = 38   ! Níveis para interpolação FG (first guess)
    config_nfgsoillevels = 4    ! Níveis de solo para FG
    config_gocartlevels  = 30   ! Níveis do GOCART (aerossóis)
/
&vertical_grid
    config_ztop             = 30000.0  ! Topo do domínio em metros (30 km)
    config_nsmterrain       = 1        ! Suavizações do terreno
    config_smooth_surfaces  = true
    config_dzmin            = 0.3      ! Espessura mínima da camada (m)
    config_nsm              = 30       ! Iterações de suavização
    config_tc_vertical_grid = true     ! Grade vertical otimizada para TC
/
&preproc_stages
    config_static_interp     = false   ! NÃO interpola dados estáticos
    config_native_gwd_static = false   ! NÃO processa GWD estático
    config_vertical_grid     = true    ! ← ÚNICA etapa ativa
    config_met_interp        = false   ! NÃO interpola dados meteorológicos
    config_input_sst         = false
    config_frac_seaice       = false
/
```

> **Atenção:** somente `config_vertical_grid = true`. Todas as demais etapas devem permanecer `false`.

---

## Grade vertical gerada (55 níveis)

A configuração `config_tc_vertical_grid = true` usa uma grade híbrida otimizada para simulação de ciclones tropicais, com resolução vertical maior nas camadas baixas da troposfera.

| Nível | Altura aproximada (m) | Sigma (η) |
|-------|----------------------|-----------|
| 1 | 0 (superfície) | 1.000 |
| 5 | 264 | 0.999 |
| 10 | 907 | 0.993 |
| 20 | 3.457 | 0.906 |
| 30 | 8.080 | 0.575 |
| 40 | 15.241 | 0.116 |
| 50 | 24.436 | 0.001 |
| 55 | 29.073 | ~0.000 |
| 56 | 30.000 (topo) | 0.000 |

---

## Submissão no cluster Jaci

### Pré-requisitos

- `x1.163842.static.nc` disponível em `${DIR_WORK}`
- Executável `build_mpas_sp/bin/mpas_init_atmosphere` compilado
- Links de tabelas físicas do build de precisão simples

### Verificar configuração antes de submeter

```bash
grep -E "config_static_interp|config_native_gwd_static|config_vertical_grid|config_met_interp" \
    namelist.init_atmosphere
```

Saída esperada:

```
    config_static_interp     = false
    config_native_gwd_static = false
    config_vertical_grid     = true
    config_met_interp        = false
```

### Submeter o job

```bash
cd /lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant
qsub job_invariant.sh
```

### Monitorar

```bash
qstat -u $USER
tail -f MPAS-Invariant.out
```

---

## Verificar o resultado

```bash
ls -lh x1.163842.invariant.nc
```

Verificar as variáveis geradas (devem aparecer em precisão simples — `float`):

```bash
ncdump -h x1.163842.invariant.nc | grep "^\s\+float\|^\s\+double" | head -10
```

---

## Exemplo de log de execução bem-sucedida

```
----------------------------------------------------------------------
Beginning MPAS-init_atmosphere Output Log File for task 0 of 128
----------------------------------------------------------------------

MPAS Init-Atmosphere Version 8.2.1

Compile-time options:
  Default real precision: double     ← build double, mas saída em single
  I/O layer: PIO 2.x

Run-time settings:
  MPI task count: 128

[...]
nCells   = 163842
nEdges   = 491520
nVertices= 327680
nVertLevels = 55

Setting up vertical levels as in 2014 TC experiments
[...]

********************************************************
   Finished running the init_atmosphere core
********************************************************

Timer information:
  total time: 4.16s   ← execução muito rápida (~4 segundos)
```

> A geração do invariant é extremamente rápida (< 5 segundos para 128 processos) porque não envolve interpolação de dados meteorológicos.

---

## Checklist

- [ ] `x1.163842.static.nc` presente no diretório de trabalho
- [ ] `namelist.init_atmosphere`: somente `config_vertical_grid = true`
- [ ] `streams.init_atmosphere`: entrada `static.nc`, saída `invariant.nc`
- [ ] Build utilizado: `build_mpas_sp` (precisão simples)
- [ ] Job submetido com `qsub job_invariant.sh`
- [ ] Arquivo `x1.163842.invariant.nc` gerado com sucesso
- [ ] Variáveis verificadas como `float` (não `double`) com `ncdump -h`

---

## Próxima Etapa

Com o `x1.163842.invariant.nc` gerado, ele é copiado para:

```
FILE_BASE/invariant/x1.163842.invariant.nc
```

e vinculado automaticamente pelo `run_mpas_forecast.bash` em todas as rodadas de previsão (ver `RUN_MODEL/README.md`).
