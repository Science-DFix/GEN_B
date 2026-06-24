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

---

## Scripts — executar nesta ordem

> Cada script deve ser executado **manualmente e individualmente**, verificando as saídas antes de avançar para o próximo.

---

### Script 1 — Pesos ESMF `1_generate_ESMF_weights.bash`

**Executado apenas uma vez** por configuração de malha.

Gera os pesos de interpolação bilinear entre a grade lat-lon 0.5° e a malha MPAS x1.163842.

#### O que editar

```bash
# Linha 3 — resolução da grade lat-lon intermediária
esmfWeightsDir=ESMF_weights   # diretório de saída (não precisa alterar)

# Linha 12 — arquivo invariant (confirme o caminho)
INVAR_FILE="/p/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.invariant.nc"
```

#### Como executar

```bash
cd /lustre/projetos/satdas/diego_workdir/SOURCE/scripts/GEN_B/prep
bash 1_generate_ESMF_weights.bash
```

#### Verificar saídas em `BTRAIN_PREP/ESMF_weights/`

```
SCRIP_latlon_0p5.nc
ESMF_MPAS_x1.163842.nc
latlon_0p5_to_MPAS_x1.163842_bilinear.nc    ← latlon → MPAS
MPAS_x1.163842_to_latlon_0p5_bilinear.nc    ← MPAS → latlon
```

---

### Script 2 — Template PTB `2_generate_template_PTB.bash`

**Executado apenas uma vez** por configuração de malha.

Cria o arquivo `template_PTB.nc` com a estrutura de dimensões do MPAS contendo as variáveis `stream_function` e `velocity_potential` zeradas.

#### O que editar

```bash
# Linha 15 — diretório de saída
DIR_WORK="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP"

# Linha 19 — arquivo mpasout de referência (qualquer rodada serve)
REF_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS/2026010100/mpasout.2026-01-02_00.00.00.nc"
```

#### Como executar

```bash
bash 2_generate_template_PTB.bash
```

#### Verificar saída

```bash
ls -lh /lustre/.../BTRAIN_PREP/template_PTB.nc
# Deve conter as variáveis stream_function e velocity_potential
ncdump -h /lustre/.../BTRAIN_PREP/template_PTB.nc | grep -E "stream_function|velocity_potential"
```

---

### Script 3 — Conversão U/V → ψ/χ `3_convert_uv_to_psichi.bash`

Converte os ventos reconstruídos do MPAS para **função de corrente (ψ)** e **potencial de velocidade (χ)**. Deve ser executado **duas vezes**: uma para f24 e outra para f48.

#### O que editar

```bash
# Linhas 44-45 — período das rodadas
idate=2025122900       # data inicial (YYYYMMDDCC)
lastidate=2026013000   # data final   (YYYYMMDDCC)

# Linha 51 — pesos ESMF (confirme o caminho)
f_wgt1="../${esmfWeightsDir}/MPAS_x1.163842_to_latlon_0p5_bilinear.nc"
f_wgt2="../${esmfWeightsDir}/latlon_0p5_to_MPAS_x1.163842_bilinear.nc"
```

#### Como executar

```bash
# Primeiro para f24:
bash 3_convert_uv_to_psichi.bash 24

# Depois para f48:
bash 3_convert_uv_to_psichi.bash 48
```

> O script gera um arquivo NCL por ciclo e o executa. Arquivos com `mpasout` ausente são pulados com aviso.

#### Verificar saídas em `BTRAIN_PREP/output/{vdate}/`

```
FULL_f24.nc    ← contém stream_function e velocity_potential
FULL_f48.nc    ← contém stream_function e velocity_potential
```

```bash
# Contar quantos FULL_f24.nc foram gerados:
find /lustre/.../BTRAIN_PREP/output -name "FULL_f24.nc" | wc -l
```

---

### Script 4 — Adicionar variáveis `4_add_variables.bash`

Adiciona ao arquivo `FULL_f{fhr}.nc` as variáveis físicas necessárias para o MPAS-JEDI. Deve ser executado **duas vezes**: uma para f24 e outra para f48.

**Variáveis calculadas:**
```bash
temperature = theta * (pressure / 100000)^(2/7)
spechum     = qv / (1 + qv)
```

**Variáveis copiadas do mpasout:**
- `surface_pressure`, `uReconstructZonal`, `uReconstructMeridional`, `relhum`

#### O que editar

```bash
# Linhas 42-43 — período (deve ser igual ao script 3)
idate=2025122900
lastidate=2026013100
```

#### Como executar

```bash
# Primeiro para f24 — gera scripts e submete job PBS:
bash 4_add_variables.bash 24

# Aguardar conclusão do job antes de rodar f48:
qstat -u $USER

# Depois para f48:
bash 4_add_variables.bash 48
```

> O script gera um job PBS (`qsub_addvar_f{fhr}h.bash`) que processa todos os ciclos em paralelo (128 por vez). Aguarde a conclusão antes de prosseguir.

#### Verificar saídas

```bash
# FULL_f24.nc deve ter as variáveis adicionadas:
ncdump -h /lustre/.../BTRAIN_PREP/output/2026010200/FULL_f24.nc | \
  grep -E "temperature|spechum|surface_pressure"
```

---

### Script 5 — Calcular perturbações `5_ncdiff.bash`

Calcula a perturbação de cada ciclo:

```
PTB_f48mf24.nc = FULL_f48.nc − FULL_f24.nc
```

#### O que editar

```bash
# Linhas 26-27 — período das valid times
vdate=2025122900
lastvdate=2026013100
```

#### Como executar

```bash
bash 5_ncdiff.bash
# Gera e submete qsub_ncdiff.bash automaticamente
```

#### Verificar saídas

```bash
# Contar PTBs gerados:
find /lustre/.../BTRAIN_PREP/output -name "PTB_f48mf24.nc" | wc -l

# Verificar tamanho de um arquivo:
ls -lh /lustre/.../BTRAIN_PREP/output/2026010200/PTB_f48mf24.nc
```

---

## Módulos necessários (cluster Jaci)

```bash
module load ncl/6.2.2
module load esmf/8.8.0-cray-turin-par
module load nco
```

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

## Checklist

- [ ] Script 1: pesos ESMF gerados (`ESMF_weights/*.nc`)
- [ ] Script 2: template PTB gerado (`template_PTB.nc`) com `stream_function` e `velocity_potential`
- [ ] Script 3 (f24): `FULL_f24.nc` gerado para cada ciclo com ψ e χ
- [ ] Script 3 (f48): `FULL_f48.nc` gerado para cada ciclo com ψ e χ
- [ ] Script 4 (f24): `FULL_f24.nc` completo com `temperature`, `spechum`, `surface_pressure`
- [ ] Script 4 (f48): `FULL_f48.nc` completo com `temperature`, `spechum`, `surface_pressure`
- [ ] Script 5: `PTB_f48mf24.nc` gerado para cada ciclo
- [ ] Total de PTBs verificado (recomendado ≥ 30 amostras)

---

## Próxima etapa

Com os arquivos `PTB_f48mf24.nc` gerados, execute `0_link_samples.bash` em `GERA_B/` para linkar as perturbações como amostras numeradas.
