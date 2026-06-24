# prep — Pré-processamento das Perturbações para a Matriz B

## O que é esta etapa?

Esta etapa transforma as **previsões brutas do MPAS-A** (arquivos `mpasout.*.nc`) em **perturbações de background** prontas para alimentar o cálculo da matriz B no MPAS-JEDI.

O método é o **NMC method**: a perturbação de cada ciclo é calculada como a diferença entre a previsão de 48h e a de 24h que chegam ao mesmo instante de análise:

```
PTB = Previsão_48h − Previsão_24h
```

---

## Fluxo completo

```
mpasout.{idate}_f24.nc  ──┐
                           ├─→ FULL_f24.nc ──┐
mpasout.{idate}_f48.nc  ──┘                  ├─→ PTB_f48mf24.nc
                           ├─→ FULL_f48.nc ──┘
```

Detalhado por etapa:

```
Pesos ESMF (1x)          → ESMF_weights/
Template PTB  (1x)       → template_PTB.nc
                                │
   ┌────────────────────────────┘
   ▼
mpasout_f24 ─→ [3] UV→ψ/χ ─→ [4] +T,q,ps ─→ FULL_f24.nc ──┐
mpasout_f48 ─→ [3] UV→ψ/χ ─→ [4] +T,q,ps ─→ FULL_f48.nc ──┤
                                                              │
                                                   [5] ncdiff ▼
                                                PTB_f48mf24.nc
```

---

## Orquestrador: `run_prep_pipeline.bash`

**Ponto de entrada principal.** Executa todas as etapas em ordem.

### Parâmetros que o usuário deve configurar

```bash
RES_LL="1.0"          # Resolução lat-lon para interpolação intermediária (graus)

REF_FILE="..."        # mpasout de qualquer rodada — usado apenas como template estrutural
                      # (ex: PREV_MPAS/2026010100/history.2026-01-02_00.00.00.nc)

LABELI="2026010100"   # Data inicial do período (YYYYMMDDCC)
LABELF="2026010500"   # Data final   do período (YYYYMMDDCC)

INIT_STEP=24          # Passo do ciclo de análise em horas (sempre 24)
FHR1=24               # Lead time da previsão curta (horas)
FHR2=48               # Lead time da previsão longa (horas)
```

> **Para o NMC method padrão**, mantenha `FHR1=24` e `FHR2=48`.

### Executar

```bash
cd /lustre/projetos/satdas/diego_workdir/SOURCE/scripts/GEN_B/prep
bash run_prep_pipeline.bash
```

---

## Etapas detalhadas

### Etapa 1 — Pesos ESMF `1_generate_ESMF_weights.bash`

**Executada apenas uma vez** por configuração de malha.

Gera os pesos de interpolação bilinear entre:
- Grade lat-lon 0.5° ↔ Malha MPAS x1.163842 (163.842 células)

**Entrada:**
- `x1.163842.invariant.nc` (para ler lat/lon das células MPAS)

**Saídas em `ESMF_weights/`:**
```
SCRIP_latlon_0p5.nc
ESMF_MPAS_x1.163842.nc
latlon_0p5_to_MPAS_x1.163842_bilinear.nc    ← latlon → MPAS
MPAS_x1.163842_to_latlon_0p5_bilinear.nc    ← MPAS → latlon
```

> A geração detecta automaticamente se o arquivo invariant é precisão simples ou dupla e ajusta o script NCL.

---

### Etapa 2 — Template PTB `2_generate_template_PTB.bash`

**Executada apenas uma vez** por configuração de malha.

Cria o arquivo `template_PTB.nc` com a estrutura de dimensões do MPAS contendo as variáveis `stream_function` e `velocity_potential` zeradas. Este template é copiado para cada rodada e preenchido com os dados calculados.

**Entrada:**
- `mpasout.*.nc` de qualquer rodada (usado apenas para extrair `theta` como base estrutural)

**Saída:**
```
BTRAIN_PREP/template_PTB.nc
```

---

### Etapa 3 — Conversão U/V → ψ/χ `3_convert_uv_to_psichi.bash <fhr>`

Converte os ventos reconstruídos (`uReconstructZonal`, `uReconstructMeridional`) do MPAS para **função de corrente (ψ)** e **potencial de velocidade (χ)** usando a rotina NCL `uv2sfvpf`.

**Argumento:** `24` ou `48` (lead time)

**Método:**
1. Interpola U/V do MPAS → grade lat-lon 0.5° (pesos ESMF)
2. Calcula ψ e χ na grade lat-lon (`uv2sfvpf`)
3. Interpola ψ e χ de volta para a malha MPAS (pesos ESMF)
4. Salva em `{vdate}/FULL_f{fhr}.nc` (usando o template)

**Entrada:** `mpasout.{vyyyy}-{vmm}-{vdd}_{vhh}.00.00.nc`

**Saída por ciclo:** `output/{vdate}/FULL_f{fhr}.nc` com `stream_function` e `velocity_potential`

---

### Etapa 4 — Adicionar variáveis `4_add_variables.bash <fhr>`

Adiciona ao arquivo `FULL_f{fhr}.nc` as variáveis físicas necessárias para o MPAS-JEDI.

**Variáveis calculadas:**
```bash
# Temperatura potencial → temperatura absoluta
temperature = theta * (pressure / 100000)^(2/7)

# Razão de mistura → umidade específica
spechum = qv / (1 + qv)
```

**Variáveis copiadas diretamente do mpasout:**
- `surface_pressure`
- `uReconstructZonal`, `uReconstructMeridional`
- `relhum`

O processamento é **paralelo** via PBS (128 ciclos simultâneos por nó).

**Saída:** `output/{vdate}/FULL_f{fhr}.nc` completo com todas as variáveis

---

### Etapa 5 — Perturbações PTB `5_ncdiff.bash`

Calcula a perturbação de cada ciclo:

```
PTB_f48mf24.nc = FULL_f48.nc − FULL_f24.nc
```

Usa `ncdiff` (NCO). O processamento é **paralelo** via PBS.

**Saída por ciclo:** `output/{vdate}/PTB_f48mf24.nc`

---

## Estrutura de saídas

```
/lustre/.../SOURCE/dataout/BTRAIN_PREP/
├── ESMF_weights/
│   ├── MPAS_x1.163842_to_latlon_0p5_bilinear.nc
│   └── latlon_0p5_to_MPAS_x1.163842_bilinear.nc
├── template_PTB.nc
└── output/
    ├── 2026010200/
    │   ├── FULL_f24.nc
    │   ├── FULL_f48.nc
    │   └── PTB_f48mf24.nc        ← perturbação final
    ├── 2026010300/
    │   └── PTB_f48mf24.nc
    ...
    └── 2026013100/
        └── PTB_f48mf24.nc
```

---

## Módulos necessários (cluster Jaci)

```bash
module load ncl/6.2.2
module load esmf/8.8.0-cray-turin-par
module load nco
```

---

## Checklist

- [ ] Pesos ESMF gerados (`ESMF_weights/*.nc`)
- [ ] Template PTB gerado (`template_PTB.nc`)
- [ ] `mpasout.*.nc` de f24 e f48 disponíveis para todo o período
- [ ] `FULL_f24.nc` e `FULL_f48.nc` gerados para cada ciclo (etapas 3+4)
- [ ] `PTB_f48mf24.nc` gerado para cada ciclo (etapa 5)
- [ ] Número total de PTBs verificado (deve ser ≥ 30 para estatística robusta)

---

## Próxima etapa

Com os arquivos `PTB_f48mf24.nc` gerados, prossiga para `GERA_B/` e execute `0_link_samples.bash` para linkar as perturbações como amostras numeradas para o cálculo da matriz B.
