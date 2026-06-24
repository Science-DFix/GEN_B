# RUN_MODEL — Geração de Rodadas MPAS-A para Matriz de Background de Erro

## Visão Geral

Esta etapa gera as **previsões de curto prazo com o modelo MPAS-A** que alimentam o cálculo da matriz de background de erro (NMC method ou ensemble). O fluxo é:

```
baixa_gfs_global.bash
        │
        ▼
  Dados GFS (.grib2)
        │
        ▼
  master_run.bash
     ┌──┴───────────────────┐
     ▼                      ▼
run_mpas_atmosphere.bash   run_mpas_forecast.bash
(Ungrib + Init)            (Previsão numérica)
     │                      │
     ▼                      ▼
x1.163842.init.nc     history.*.nc / diag.*.nc
```

---

## Scripts

| Script | Função |
|--------|--------|
| `baixa_gfs_global.bash` | Baixa dados de análise GFS 0.25° do servidor Pelican (Duke) |
| `master_run.bash` | **Ponto de entrada principal.** Configura parâmetros e chama Init + Forecast |
| `run_mpas_atmosphere.bash` | Executa ungrib (WPS) e `init_atmosphere_model` para gerar a condição inicial |
| `run_mpas_forecast.bash` | Executa `mpas_atmosphere` para gerar a previsão |

---

## Passo 1 — Download dos Dados GFS

Edite `baixa_gfs_global.bash` para definir o período desejado:

```bash
# --- CONFIGURAÇÃO ---
CICLO="00"          # Ciclo sinótico: 00, 06, 12 ou 18 (UTC)

for ano in $(seq 2025 2025); do        # Ano(s)
    for mes in $(seq -f "%02g" 12 12); do   # Mês(es)
        for dia in $(seq -f "%02g" 01 15); do  # Dia(s)
```

> **Para a matriz de background de erro (NMC method)** é necessário ao menos **30 dias** de dados, com previsões de **24h e 48h** para o mesmo instante de análise.

Execute:

```bash
bash baixa_gfs_global.bash
```

Os arquivos são salvos em:

```
/lustre/projetos/satdas/diego_workdir/SOURCE/datainput/gfs/{ANOMESDIACICLO}/
  gfs.0p25.{ANOMESDIACICLO}.f000.grib2
  gfs.0p25.{ANOMESDIACICLO}.f003.grib2
  ...
  gfs.0p25.{ANOMESDIACICLO}.f048.grib2
```

---

## Passo 2 — Configurar e Rodar o Master

Todo o controle da rodada é feito **exclusivamente no arquivo `master_run.bash`**. Os sub-scripts (`run_mpas_atmosphere.bash` e `run_mpas_forecast.bash`) herdam as variáveis via `export` e não precisam ser editados.

### 2.1 Parâmetros que o usuário deve configurar

Abra `master_run.bash` e ajuste a seção **2 a 5**:

#### Precisão numérica (seção 2)

```bash
export PRECISION="double"   # "double" (padrão) ou "single"
```

| Valor | Build utilizado | Observação |
|-------|----------------|------------|
| `double` | `build-mpich` | Padrão recomendado |
| `single` | `build_mpas_sp` | Habilita SfcCorrected no MPAS-JEDI |

O diretório de binários (`DIR_EXE`) é selecionado automaticamente conforme a precisão escolhida.

#### Configurações da previsão (seção 4)

```bash
export RUN_DURATION="2_00:00:00"      # Duração total: "D_HH:MM:SS"
export OUTPUT_INTERVAL="06:00:00"     # Frequência de saída history (HH:MM:SS)
export DIAG_INTERVAL="03:00:00"       # Frequência de diagnóstico (HH:MM:SS)
export DT="360"                        # Time step em segundos
export RADT_INTERVAL="00:30:00"       # Intervalo de chamada da radiação
export SST_UPDATE="false"             # Atualizar SST durante a previsão: true/false
export PHYSICS_SUITE="mesoscale_reference"  # Suite de física do MPAS
export IAU_OPTION="off"               # Incremental Analysis Update: on/off
```

> **Para o NMC method:** use `RUN_DURATION="2_00:00:00"` (48h) e `IAU_OPTION="off"`.  
> **IAU_OPTION="on"** exige o arquivo `x1.163842.AmB.*.nc` já disponível (usado em ciclos de assimilação).

#### Período de rodada (seção 5)

```bash
ANOS="2026"       # Um ou mais anos separados por espaço: "2025 2026"
MESES="01"        # Um ou mais meses: "01 02 03"
DIAS="01"         # Um ou mais dias: "01 02 03"
HORAS="00"        # Horários sinóticos: "00 06 12 18"
```

O script itera automaticamente em todos os `ANOS × MESES × DIAS × HORAS`.

### 2.2 Executar

```bash
bash master_run.bash
```

O progresso é registrado em `execucao_total.log` no diretório corrente.

---

## Saídas Geradas

### Init (`run_mpas_atmosphere.bash`)

```
/lustre/projetos/satdas/diego_workdir/SOURCE/rodadas/MPAS-A/{TIMESTAMP}/
  x1.163842.init.nc          ← condição inicial do MPAS-A
  met_data/FILE:*            ← intermediários do ungrib
  log.ungrib.out
  log.init_atmosphere.0000.out
  namelist.wps
  namelist.init_atmosphere
  streams.init_atmosphere
  tempo.log                  ← tempo de execução
```

### Forecast (`run_mpas_forecast.bash`)

```
/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/{TIMESTAMP}/
  history.{TIMESTAMP}.nc     ← saída principal (a cada OUTPUT_INTERVAL)
  diag.{TIMESTAMP}.nc        ← diagnósticos (a cada DIAG_INTERVAL)
  mpasout.{TIMESTAMP}.nc     ← restart
  log.atmosphere.0000.out
  log.atmosphere.0000.err
  tempo.log                  ← tempo de execução
```

---

## Exemplo de Rodada Completa

**Objetivo:** Gerar previsões de 48h para 01/jan/2026 00Z, com precisão dupla e sem IAU.

### 1. Baixar os dados GFS

Em `baixa_gfs_global.bash`:

```bash
CICLO="00"
for ano in $(seq 2026 2026); do
    for mes in $(seq -f "%02g" 01 01); do
        for dia in $(seq -f "%02g" 01 01); do
            ...
            for prev in $(seq -f "%02g" 00 3 48); do
```

```bash
bash baixa_gfs_global.bash
```

Resultado esperado em `/lustre/.../datainput/gfs/2026010100/`:
```
gfs.0p25.2026010100.f000.grib2
gfs.0p25.2026010100.f003.grib2
...
gfs.0p25.2026010100.f048.grib2
```

### 2. Configurar o master

Em `master_run.bash`:

```bash
export PRECISION="double"
export RUN_DURATION="2_00:00:00"
export OUTPUT_INTERVAL="06:00:00"
export DIAG_INTERVAL="03:00:00"
export DT="360"
export RADT_INTERVAL="00:30:00"
export SST_UPDATE="false"
export IAU_OPTION="off"

ANOS="2026"
MESES="01"
DIAS="01"
HORAS="00"
```

### 3. Executar

```bash
bash master_run.bash
```

### 4. Verificar o log

```bash
tail -f execucao_total.log
```

Saída esperada ao final:

```
======================================================
 PRECISÃO : double
 BUILD    : /lustre/projetos/satdas/diego_workdir/build-mpich
 Iniciado : Tue Jun 24 10:00:00 UTC 2026
======================================================
=== INICIANDO CICLO 2026010100 EM Tue Jun 24 10:00:00 UTC 2026 ===
ungrib OK — 17 arquivos FILE:* gerados
Rodando init_atmosphere_model [double] com 256 processos...
--- Init SUCESSO: 2026010100 [double] ---
Rodando mpas_atmosphere [double] com 256 processos...
--- Forecast SUCESSO: 2026010100 [double] ---
SUCESSO: 2026010100 | Init: 300s | Fcst: 7200s
=== CONCLUÍDO EM Tue Jun 24 12:00:00 UTC 2026 ===
```

---

## Checklist de Pré-execução

- [ ] Dados GFS baixados para o período em `/lustre/.../datainput/gfs/{TIMESTAMP}/`
- [ ] `x1.163842.grid.nc`, `x1.163842.static.nc` e `x1.163842.graph.info.part.256` disponíveis em `FILE_BASE/60km/`
- [ ] `x1.163842.invariant.nc` disponível em `FILE_BASE/invariant/`
- [ ] `namelist.wps`, `namelist.init_atmosphere`, `streams.init_atmosphere` em `FILE_BASE/`
- [ ] `namelist.atmosphere`, `streams.atmosphere`, `stream_list.atmosphere.*` em `FILE_BASE/core_atmosphere/`
- [ ] Ambiente MPICH carregado (`env_wrf_wps.bash`)
- [ ] Se `IAU_OPTION="on"`: arquivo `x1.163842.AmB.*.nc` disponível
- [ ] Se `SST_UPDATE="true"`: arquivo `x1.163842.sfc_update.nc` disponível

---

## Próxima Etapa

Com as previsões de 48h geradas, prossiga para o cálculo da **matriz de background de erro** utilizando os campos `history.*.nc` como entrada.
