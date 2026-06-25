# FILE_BASE — Arquivos de Configuração Base do MPAS-A

Este diretório contém os arquivos de configuração (namelists e streams) utilizados como **templates base** pelos scripts de inicialização e previsão do MPAS-A. Os scripts copiam esses arquivos para o diretório de trabalho de cada rodada e ajustam automaticamente as datas e parâmetros via `sed`.

> Os arquivos binários de malha (`x1.163842.grid.nc`, `x1.163842.static.nc`, `x1.163842.graph.info.part.*`, `x1.163842.invariant.nc`) não estão versionados aqui por serem muito grandes. Consulte a seção [Arquivos não versionados](#arquivos-não-versionados) abaixo.

---

## Estrutura

```
FILE_BASE/
├── namelist.wps               ← configuração do ungrib (WPS)
├── namelist.init_atmosphere   ← configuração do init_atmosphere_model
├── streams.init_atmosphere    ← streams do init (entrada/saída)
└── core_atmosphere/
    ├── namelist.atmosphere        ← configuração do mpas_atmosphere (previsão)
    ├── namelist.atmosphere.backup ← backup do namelist original
    ├── streams.atmosphere         ← streams da previsão
    ├── stream_list.atmosphere.output      ← variáveis da saída history
    ├── stream_list.atmosphere.diagnostics ← variáveis dos diagnósticos
    └── stream_list.atmosphere.surface     ← variáveis de atualização SST
```

---

## Arquivos da raiz

### `namelist.wps`

Configuração do **WPS ungrib** para decodificação dos dados GFS em formato intermediário.

**Campos preenchidos automaticamente pelo script:**

| Campo | Substituído por |
|-------|----------------|
| `start_date` | data de início da rodada (`run_mpas_atmosphere.bash`) |
| `end_date` | data de fim (+2 dias da rodada) |

**Campos fixos:**
```fortran
wrf_core         = 'ARW'      ! núcleo (obrigatório para ungrib)
interval_seconds = 10800      ! intervalo entre arquivos GFS (3h)
out_format       = 'WPS'      ! formato de saída do ungrib
prefix           = 'FILE'     ! prefixo dos arquivos intermediários
```

---

### `namelist.init_atmosphere`

Configuração do **`init_atmosphere_model`** para geração da condição inicial (`x1.163842.init.nc`).

**Campos preenchidos automaticamente pelo script:**

| Campo | Substituído por |
|-------|----------------|
| `config_start_time` | data de início da rodada |
| `config_stop_time` | mesma data de início (init é instantâneo) |

**Campos fixos importantes:**

```fortran
config_init_case       = 7     ! interpolação de dados reais (GFS)
config_nvertlevels     = 55    ! níveis verticais atmosféricos
config_nsoillevels     = 4     ! níveis de solo
config_nfglevels       = 38    ! níveis para interpolação first-guess
config_ztop            = 30000.0  ! topo do domínio (30 km)
config_tc_vertical_grid = true    ! grade vertical otimizada para TC

! etapas ativas:
config_vertical_grid   = true
config_met_interp      = true
config_frac_seaice     = true
```

> **Atenção:** `config_met_interp = true` aqui (diferente do `invariant/`, onde é `false`). Este namelist interpola dados meteorológicos GFS para gerar o `init.nc`.

---

### `streams.init_atmosphere`

Define entrada e saída do `init_atmosphere_model`:

| Stream | Arquivo | Descrição |
|--------|---------|-----------|
| `input` | `x1.163842.static.nc` | malha e dados estáticos |
| `output` | `x1.163842.init.nc` | condição inicial gerada |

---

## Arquivos de `core_atmosphere/`

### `namelist.atmosphere`

Configuração do **`mpas_atmosphere`** (previsão numérica). É o namelist principal da previsão.

**Campos preenchidos automaticamente pelo `run_mpas_forecast.bash`:**

| Campo | Variável do master |
|-------|--------------------|
| `config_start_time` | `TIMESTAMP` |
| `config_run_duration` | `RUN_DURATION` |
| `config_dt` | `DT` |
| `config_radtlw_interval` | `RADT_INTERVAL` |
| `config_radtsw_interval` | `RADT_INTERVAL` |
| `config_sst_update` | `SST_UPDATE` |
| `config_IAU_option` | `IAU_OPTION` |

**Campos fixos importantes — o usuário não precisa editar:**

```fortran
! Dinâmica
config_split_dynamics_transport = true
config_number_of_sub_steps      = 2
config_dynamics_split_steps     = 3
config_horiz_mixing             = '2d_smagorinsky'
config_len_disp                 = 60000.0    ! resolução 60km
config_coef_3rd_order           = 0.25
config_epssm                    = 0.1

! Amortecimento
config_zd    = 22000.0    ! camada de amortecimento acima de 22km
config_xnutr = 0.2

! Física
config_physics_suite = 'mesoscale_reference'

! JEDI
config_jedi_da = true
```

> **Para alterar parâmetros da previsão**, edite apenas o `master_run.bash` em `RUN_MODEL/`. O namelist é preenchido automaticamente.

---

### `streams.atmosphere`

Define todos os streams de I/O da previsão:

| Stream | Arquivo gerado | Intervalo padrão |
|--------|---------------|-----------------|
| `input` | `x1.163842.init.nc` | inicial |
| `invariant` | `invariant.nc` | inicial |
| `restart` | `restart.*.nc` | 1 dia |
| `output` (history) | `history.*.nc` | 6h |
| `diagnostics` | `diag.*.nc` | 3h |
| `surface` | `x1.163842.sfc_update.nc` | sob demanda (SST) |
| `iau` | `x1.163842.AmB.*.nc` | sob demanda (IAU) |
| `da_state` | `mpasout.*.nc` | 6h |

> Os intervalos de `output` e `diagnostics` são sobrescritos automaticamente pelo `run_mpas_forecast.bash` conforme `OUTPUT_INTERVAL` e `DIAG_INTERVAL` do master.

---

### `stream_list.atmosphere.output`

Lista as variáveis gravadas nos arquivos `history.*.nc`. Contém campos 3D completos do modelo (dinâmica, física, química) para uso em pós-processamento e geração da matriz B.

### `stream_list.atmosphere.diagnostics`

Lista as variáveis gravadas nos arquivos `diag.*.nc`. Contém campos interpolados em níveis de pressão isobárica (50, 100, 200, 250, 500, 700, 850, 925 hPa) para verificação e diagnóstico.

### `stream_list.atmosphere.surface`

Contém apenas `sst` e `xice` — usado quando `SST_UPDATE=true` no master para atualizar a temperatura da superfície do mar durante a previsão.

---

## Arquivos não versionados

Os arquivos binários de malha não estão neste repositório. Devem estar disponíveis no cluster em:

```
FILE_BASE/
├── 60km/
│   ├── x1.163842.grid.nc              ← malha horizontal
│   ├── x1.163842.static.nc            ← dados estáticos (topografia, vegetação)
│   └── x1.163842.graph.info.part.256  ← decomposição para 256 processos
└── invariant/
    ├── x1.163842.invariant.nc         ← grade vertical (gerado em invariant/)
    └── x1.163842.graph.info.part.64   ← decomposição para 64 processos
```

---

## Qual script usa qual arquivo

| Arquivo | Script |
|---------|--------|
| `namelist.wps` | `RUN_MODEL/run_mpas_atmosphere.bash` |
| `namelist.init_atmosphere` | `RUN_MODEL/run_mpas_atmosphere.bash` |
| `streams.init_atmosphere` | `RUN_MODEL/run_mpas_atmosphere.bash` |
| `core_atmosphere/namelist.atmosphere` | `RUN_MODEL/run_mpas_forecast.bash` |
| `core_atmosphere/streams.atmosphere` | `RUN_MODEL/run_mpas_forecast.bash` |
| `core_atmosphere/stream_list.atmosphere.*` | `RUN_MODEL/run_mpas_forecast.bash` |
