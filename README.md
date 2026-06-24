# GEN_B — Geração da Matriz de Background de Erro para MPAS-JEDI

Sistema de scripts e documentação para geração da **matriz de covariância de erros de background (matriz B)** utilizada no sistema de assimilação de dados MPAS-JEDI (BUMP/SABER), desenvolvido no CPTEC/INPE.

---

## Visão Geral

A matriz B descreve a estrutura espacial e entre variáveis dos erros de background do modelo MPAS-A. Ela é calibrada pelo método NMC a partir de diferenças entre previsões de 24h e 48h válidas para o mesmo instante de análise.

O fluxo completo envolve três etapas principais, executadas nesta ordem:

```
1. RUN_MODEL      → Gera previsões de 48h com MPAS-A
2. invariant      → Gera a grade vertical do modelo (uma vez)
3. GERA_B/prep    → Pré-processa as perturbações (PTB = F48 − F24)
4. GERA_B         → Calibra a matriz B (VBAL → HDIAG → NICAS → Validação)
```

---

## Estrutura do Repositório

```
GEN_B/
├── RUN_MODEL/          # Download GFS e rodadas MPAS-A (Init + Forecast)
│   ├── README.md
│   ├── baixa_gfs_global.bash
│   ├── master_run.bash
│   ├── run_mpas_atmosphere.bash
│   └── run_mpas_forecast.bash
│
├── invariant/          # Geração do arquivo de grade vertical (executar uma vez)
│   ├── README.md
│   ├── job_invariant.sh
│   ├── namelist.init_atmosphere
│   └── streams.init_atmosphere
│
└── GERA_B/             # Calibração da matriz B
    ├── README.md
    ├── prep/           # Pré-processamento das perturbações
    │   ├── README.md
    │   └── run_prep_pipeline.bash   ← orquestrador do pré-processamento
    ├── 0_link_samples.bash
    ├── 1_run_vbal.bash
    ├── 2a_run_hdiag_var.bash
    ├── 2b_run_hdiag_var_hydrometeors.bash
    ├── 2c_modify_diagnostics.bash
    ├── 3_run_nicas_split.bash
    ├── 4_merge_nicas.bash
    ├── 5_SO.bash
    └── 6_dirac.bash
```

---

## Pré-requisitos

| Componente | Versão | Uso |
|-----------|--------|-----|
| MPAS-A | 8.2.1 | Modelo atmosférico |
| MPAS-JEDI | — | Assimilação de dados |
| BUMP/SABER | — | Calibração da matriz B |
| WPS (ungrib) | — | Processamento GFS |
| NCL | 6.2.2 | Interpolação ESMF |
| ESMF | 8.8.0 | Pesos de interpolação |
| NCO | — | Operações NetCDF |
| MPI | MPICH | Execução paralela |

**Cluster:** Jaci (CPTEC/INPE) — fila PBS (`pesqmidi`, `pesqextra`)

---

## Como executar

### 1. Gerar previsões MPAS-A

Configure o período e execute:

```bash
cd RUN_MODEL/
bash baixa_gfs_global.bash     # baixa dados GFS
bash master_run.bash            # roda Init + Forecast
```

Consulte [`RUN_MODEL/README.md`](RUN_MODEL/README.md) para detalhes de configuração.

### 2. Gerar o invariant (apenas uma vez)

```bash
cd invariant/
qsub job_invariant.sh
```

Consulte [`invariant/README.md`](invariant/README.md).

### 3. Pré-processar as perturbações

```bash
cd GERA_B/prep/
# editar LABELI, LABELF e REF_FILE em run_prep_pipeline.bash
bash run_prep_pipeline.bash
```

Consulte [`GERA_B/prep/README.md`](GERA_B/prep/README.md).

### 4. Calibrar a matriz B

```bash
cd GERA_B/
bash 0_link_samples.bash
bash 1_run_vbal.bash
bash 2a_run_hdiag_var.bash
bash 2c_modify_diagnostics.bash
bash 3_run_nicas_split.bash
bash 4_merge_nicas.bash
bash 5_SO.bash        # validação
bash 6_dirac.bash     # validação
```

Consulte [`GERA_B/README.md`](GERA_B/README.md) para a descrição completa de cada etapa.

---

## Variáveis de controle da matriz B

| Variável | Descrição |
|---------|-----------|
| `stream_function` | Função de corrente (ψ) |
| `velocity_potential` | Potencial de velocidade (χ) |
| `temperature` | Temperatura absoluta |
| `spechum` | Umidade específica |
| `surface_pressure` | Pressão em superfície |

---

## Instituição

**CPTEC/INPE** — Centro de Previsão de Tempo e Estudos Climáticos  
Instituto Nacional de Pesquisas Espaciais  
Cachoeira Paulista, SP — Brasil
