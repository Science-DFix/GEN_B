# GERA_B — Geração da Matriz de Background de Erro (MPAS-JEDI / BUMP/SABER)

## Visão Geral

Esta etapa calibra a **matriz de covariância de erros de background (matriz B)** para uso no sistema de assimilação de dados MPAS-JEDI. O processo é dividido em dois blocos:

| Bloco | Diretório | Descrição |
|-------|-----------|-----------|
| **Pré-processamento** | `prep/` | Gera as perturbações PTB = F48 − F24 a partir das previsões MPAS-A |
| **Processamento** | `GERA_B/` (este diretório) | Calibra VBAL, HDIAG, NICAS e valida com testes Dirac e Single-Obs |

---

## Fluxo completo de processamento

```
[prep/] PTB_f48mf24_*.nc
              │
              ▼
   0_link_samples.bash          → samples/PTB_f48mf24_001.nc ... _NNN.nc
              │
              ▼
   1_run_vbal.bash              → VBAL/ (balanço vertical ψ→χ, T, ps)
              │                   samplesUnbalanced/PTB_f48mf24_*.nc
              ▼
   2a_run_hdiag_var.bash        → HDIAG_VAR/vargroup1/ (stddev, cor_rh, cor_rv)
   2b_run_hdiag_var_            → HDIAG_VAR/vargroup2/ (hidrometeoros — opcional)
      hydrometeors.bash
              │
              ▼
   2c_modify_diagnostics.bash   → HDIAG_VAR/merge/ (ajuste de correlações/variâncias)
              │
              ▼
   3_run_nicas_split.bash       → NICAS.split/{variável}/ (NICAS por variável)
              │
              ▼
   4_merge_nicas.bash           → NICAS.split/merge/ (NICAS unificado)
              │
         ┌────┴────┐
         ▼         ▼
   5_SO.bash    6_dirac.bash    Testes de validação
```

---

## Scripts auxiliares (ajuste fino)

| Script | Quando usar |
|--------|-------------|
| `etc_modify_cor.bash` | Ajustar manualmente os comprimentos de correlação horizontal/vertical |
| `etc_modify_var.bash` | Ajustar manualmente as variâncias (stddev) |
| `etc_modify_missing.bash` | Corrigir missing values nos hidrometeoros |

Esses scripts são chamados automaticamente pelo `2c_modify_diagnostics.bash` quando as flags `isTuneHdiag=1` ou `isTuneVar=1` estão ativas.

---

## Parâmetros comuns a todos os scripts

Os scripts de processamento compartilham os mesmos parâmetros de data e arquivos de background. **Todos devem ser consistentes entre si:**

```bash
BG_FILE="...PREV_MPAS/2026010100/mpasout.2026-01-02_00.00.00.nc"
DATE_YAML="2026-01-02T00:00:00Z"
DATE_FILE="2026-01-02_00.00.00"
```

> `DATE_FILE` determina automaticamente o `INIT_DATE` (ex: `2026010200`) e o `INIT_FILE` correspondente.

---

## Etapa 0 — Linkar amostras `0_link_samples.bash`

Cria links simbólicos numerados dos arquivos PTB para o diretório `samples/`:

```bash
# Configurar o período das valid times disponíveis
date=2025123100
lastdate=2026013100
```

**Saída:**
```
GEN_B/proc/samples/
  PTB_f48mf24_001.nc → .../output/2025123100/PTB_f48mf24.nc
  PTB_f48mf24_002.nc → .../output/2026010100/PTB_f48mf24.nc
  ...
  PTB_f48mf24_032.nc → .../output/2026013100/PTB_f48mf24.nc
```

**Verificar:**
```bash
ls GEN_B/proc/samples/ | wc -l   # deve ser igual a NMEMBERS
```

---

## Etapa 1 — Balanço Vertical `1_run_vbal.bash`

Calibra o operador de **balanço vertical (VBAL)** entre as variáveis de controle usando o bloco SABER `BUMP_VerticalBalance`.

### Parâmetros a configurar

```bash
BG_FILE="..."          # mpasout do ciclo de referência
DATE_YAML="..."        # data do background (formato ISO)
DATE_FILE="..."        # data do background (formato arquivo)
NMEMBERS=32            # número de amostras em samples/
NTASKS=64              # processos MPI
PBS_QUEUE="pesqextra"
PBS_WALLTIME="06:00:00"
```

### Balanços calibrados

```yaml
- velocity_potential  ←  stream_function   (regressão diagonal)
- temperature         ←  stream_function
- surface_pressure    ←  stream_function
```

### Executar

```bash
bash 1_run_vbal.bash
# Submete run_vbal.pbs automaticamente
```

### Saídas

```
GEN_B/proc/VBAL/
  mpas_vbal.nc
  mpas_vbal_local_000064-*.nc
  run_vbal.runlog

GEN_B/proc/samplesUnbalanced/
  PTB_f48mf24_001.nc ... _032.nc    ← amostras com parte balanceada removida
```

---

## Etapa 2a — Diagnóstico HDIAG (variáveis dinâmicas) `2a_run_hdiag_var.bash`

Calcula **desvio padrão** e **comprimentos de correlação** horizontal e vertical para as 5 variáveis de controle dinâmicas usando `BUMP_NICAS` em modo diagnóstico.

### Variáveis processadas

```
stream_function, velocity_potential, temperature, spechum, surface_pressure
```

### Configurações BUMP relevantes

```yaml
sampling:
  computation grid size: 12000    # tamanho da grade para amostragem
  diagnostic grid size: 1000      # tamanho da grade diagnóstica
  distance classes: 10            # classes de distância horizontal
  distance class width: 1000.0e3  # largura de cada classe (m)
  reduced levels: 10              # níveis verticais reduzidos
  averaging length-scale: 3000e3  # escala de média

variance:
  objective filtering: true       # filtragem objetiva das variâncias
  initial length-scale: 3000e3    # escala inicial para filtragem
```

### Executar

```bash
bash 2a_run_hdiag_var.bash
# Submete run_hdiag_var.pbs
```

### Saídas em `HDIAG_VAR/vargroup1/`

```
mpas.stddev.nc     ← desvio padrão por variável e nível
mpas.cor_rh.nc     ← comprimentos de correlação horizontal
mpas.cor_rv.nc     ← comprimentos de correlação vertical
```

---

## Etapa 2b — Diagnóstico HDIAG (hidrometeoros) `2b_run_hdiag_var_hydrometeors.bash` *(opcional)*

Mesmo processo da etapa 2a, mas para as variáveis de hidrometeoros:

```
qc (nuvem líquida), qi (gelo), qr (chuva), qs (neve), qg (granizo)
```

Ativado quando `include_hydrometeor=1` no script `2c_modify_diagnostics.bash`.

**Saídas em `HDIAG_VAR/vargroup2/`:** `mpas.stddev.nc`, `mpas.cor_rh.nc`, `mpas.cor_rv.nc`

---

## Etapa 2c — Modificar diagnósticos `2c_modify_diagnostics.bash`

Mescla e ajusta os arquivos diagnósticos antes do NICAS.

### Flags de controle

```bash
include_hydrometeor=2   # 1: incluir hidrometeoros (mescla vargroup1+2), 2: não incluir
isTuneHdiag=1           # 1: ajustar comprimentos de correlação (etc_modify_cor.bash)
isTuneVar=1             # 1: ajustar variâncias (etc_modify_var.bash)
```

### Executar

```bash
bash 2c_modify_diagnostics.bash
```

### Saídas em `HDIAG_VAR/merge/`

```
mpas.cor_rh.nc    ← comprimentos de correlação (ajustados)
mpas.cor_rv.nc    ← comprimentos de correlação vertical (ajustados)
mpas.stddev.nc    ← desvio padrão (ajustado)
```

> Estes arquivos em `merge/` são a entrada do NICAS (etapa 3).

---

## Etapa 3 — NICAS por variável `3_run_nicas_split.bash`

Calibra o operador de **interpolação e normalização** (NICAS) para cada variável de controle **separadamente** (estratégia univariada).

### Variáveis processadas

```
stream_function, velocity_potential, temperature, spechum, surface_pressure
```

Cada variável cria um subdiretório próprio e submete um job PBS independente.

### Parâmetros relevantes

```yaml
nicas:
  resolution: 8                  # resolução da grade NICAS
  max horizontal grid size: 15000  # tamanho máximo (30000 para hidrometeoros)
```

### Executar

```bash
bash 3_run_nicas_split.bash
# Submete 5 jobs PBS independentes (um por variável)
```

### Saídas em `NICAS.split/{variável}/`

```
mpas_nicas.nc                         ← NICAS global
mpas_nicas_local_NNNNNN-*.nc          ← NICAS local (por tarefa MPI)
mpas_nicas_grids_local_NNNNNN-*.nc    ← grades NICAS locais
mpas.nicas_norm.nc                    ← normalização
mpas.dirac_nicas.nc                   ← teste Dirac interno do NICAS
```

> Aguardar conclusão de **todos os 5 jobs** antes de prosseguir para a etapa 4.

---

## Etapa 4 — Merge NICAS `4_merge_nicas.bash`

Unifica os arquivos NICAS de todas as variáveis em um único conjunto usando `ncks` (NCO). Detecta automaticamente o número de arquivos locais gerados.

### Executar

```bash
bash 4_merge_nicas.bash
# Submete merge_nicas.pbs
```

### Saídas em `NICAS.split/merge/`

```
mpas_nicas.nc
mpas_nicas_local_NNNNNN-*.nc
mpas_nicas_grids_local_NNNNNN-*.nc
mpas.nicas_norm.nc
mpas.dirac_nicas.nc
```

---

## Etapa 5 — Single Observation Test `5_SO.bash`

Teste de validação do sistema B completo usando a aplicação **3D-Var** do MPAS-JEDI com **duas observações sintéticas**:

- `SO_T`: temperatura do ar em pressão ~788 hPa (30.3°S, 130°E)
- `SO_U`: vento zonal em pressão ~777 hPa (57.8°N, 357.7°E)

### Parâmetros a configurar

```bash
BG_FILE="..."              # mpasout de referência
DATE_YAML="..."            # data da análise
TIME_WINDOW_BEGIN="..."    # início da janela de assimilação (3h antes do background)
NTASKS=512                 # processos MPI (mais processos que as etapas anteriores)
PBS_QUEUE="pesqextra"
PBS_WALLTIME="04:30:00"
```

> **Atenção:** usa `build-jedi` (precisão dupla), diferente das etapas anteriores que usam `build-mpich`.

### Executar

```bash
bash 5_SO.bash
# Submete run_SO.pbs
```

### Saídas em `proc/SO/`

```
an.{DATE}.nc        ← análise resultante
obsout_SO_T.h5      ← diagnósticos da observação de temperatura
obsout_SO_U.h5      ← diagnósticos da observação de vento
run_SO.runlog       ← log detalhado do JEDI
```

**Verificação:** o incremento de análise deve ser **fisicamente consistente** — perturbação positiva centrada na localização da observação.

---

## Etapa 6 — Teste Dirac `6_dirac.bash`

Aplica a matriz B a um **vetor delta** (Dirac) para visualizar a estrutura espacial das covariâncias. Útil para diagnóstico visual da qualidade da matriz B.

### Parâmetros a configurar

```bash
DIRAC_VAR="temperature"      # variável a testar
DIRAC_LEVEL=10               # nível vertical do impulso
DIRAC_LAT="30.31011691"      # latitude do ponto
DIRAC_LON="130.11182691"     # longitude do ponto
NTASKS=64
```

### Executar

```bash
bash 6_dirac.bash
# Submete run_dirac.pbs
```

### Saída em `proc/Dirac/test_{variável}/`

```
mpas.dirac.nc    ← resposta da matriz B ao impulso Dirac
```

**Verificação:** a resposta deve mostrar estrutura de covariância **localizada e suave** em torno do ponto especificado.

---

## Resumo dos diretórios gerados

```
/lustre/.../SOURCE/dataout/GEN_B/proc/
├── samples/                  ← links das PTBs (entrada do VBAL)
├── samplesUnbalanced/        ← PTBs após remoção do balanço (entrada do HDIAG)
├── VBAL/                     ← operador de balanço vertical calibrado
├── HDIAG_VAR/
│   ├── vargroup1/            ← diagnósticos vars dinâmicas
│   ├── vargroup2/            ← diagnósticos hidrometeoros (opcional)
│   └── merge/                ← diagnósticos finais (entrada do NICAS)
├── NICAS.split/
│   ├── stream_function/
│   ├── velocity_potential/
│   ├── temperature/
│   ├── spechum/
│   ├── surface_pressure/
│   └── merge/                ← NICAS final (entrada do SO e Dirac)
├── SO/                       ← Single Observation Test
└── Dirac/                    ← Teste Dirac
```

---

## Checklist de execução

- [ ] **prep/** concluída: `PTB_f48mf24.nc` para todos os ciclos
- [ ] **0**: `samples/PTB_f48mf24_001.nc ... _NNN.nc` linkados
- [ ] **1**: VBAL calibrado; `samplesUnbalanced/` populado
- [ ] **2a**: `HDIAG_VAR/vargroup1/mpas.stddev.nc` gerado
- [ ] **2b** *(se hidrometeoros)*: `HDIAG_VAR/vargroup2/mpas.stddev.nc` gerado
- [ ] **2c**: `HDIAG_VAR/merge/mpas.{stddev,cor_rh,cor_rv}.nc` ajustados
- [ ] **3**: NICAS calibrado para cada variável (aguardar todos os 5 jobs)
- [ ] **4**: `NICAS.split/merge/mpas_nicas.nc` gerado
- [ ] **5**: Single Obs Test com incremento fisicamente consistente
- [ ] **6**: Dirac com estrutura de covariância coerente
