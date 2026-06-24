#!/bin/bash
set -euo pipefail

# ============================================================
# Ambiente
# ============================================================
source /p/projetos/satdas/diego_workdir/env_wrf_wps.bash
module load ncl/6.2.2
module load esmf/8.8.0-cray-turin-par

# ============================================================
# Configuração fixa do seu ambiente
# ============================================================
DIR_PREV="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/PREV_MPAS"
DIR_ALL_PREV="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/ALL_PREV"
DIR_WORK="/lustre/projetos/satdas/diego_workdir/SOURCE/dataout/BTRAIN_PREP"

GRID_FILE="/lustre/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/60km/x1.163842.grid.nc"
INVAR_FILE="/p/projetos/satdas/diego_workdir/SOURCE/FILE_BASE/invariant/x1.163842.invariant.nc"

# Resolução da grade lat-lon alvo
LL_RES="${1:-1.0}"
LL_TAG="${LL_RES}x${LL_RES}"

ESMF_DIR="${DIR_WORK}/ESMF_weights"
mkdir -p "${ESMF_DIR}"
cd "${ESMF_DIR}"

echo "== (1) Gerando SCRIP + pesos ESMF em: ${ESMF_DIR}"

# ============================================================
# Verificações
# ============================================================
for exe in ncl ESMF_RegridWeightGen ncdump; do
    if ! command -v "${exe}" >/dev/null 2>&1; then
        echo "ERRO: executável não encontrado no PATH: ${exe}"
        exit 1
    fi
done

if [ ! -s "${GRID_FILE}" ]; then
    echo "ERRO: GRID_FILE não encontrado: ${GRID_FILE}"
    exit 1
fi

if [ ! -s "${INVAR_FILE}" ]; then
    echo "ERRO: INVAR_FILE não encontrado: ${INVAR_FILE}"
    exit 1
fi

# ============================================================
# Limpeza prévia
# ============================================================
rm -f SCRIP_MPAS_x1.163842.nc
rm -f "SCRIP_latlon_${LL_TAG}.nc"
rm -f "wgt_mpas_to_latlon_${LL_TAG}.nc"
rm -f "wgt_latlon_to_mpas_${LL_TAG}.nc"
rm -f PET*.RegridWeightGen.Log
rm -f gen_scrip_and_weights.ncl

# ============================================================
# Script NCL para gerar os dois arquivos SCRIP em RADIANOS
# ============================================================
cat > gen_scrip_and_weights.ncl << 'EOF'
begin
  grid_file  = getenv("GRID_FILE")
  invar_file = getenv("INVAR_FILE")
  ll_res_s   = getenv("LL_RES")
  ll_tag     = getenv("LL_TAG")

  if (.not. isdefined("grid_file")) then
    print("ERRO: GRID_FILE nao definido")
    exit
  end if
  if (.not. isdefined("invar_file")) then
    print("ERRO: INVAR_FILE nao definido")
    exit
  end if
  if (.not. isdefined("ll_res_s")) then
    print("ERRO: LL_RES nao definido")
    exit
  end if
  if (.not. isdefined("ll_tag")) then
    print("ERRO: LL_TAG nao definido")
    exit
  end if

  ll_res = tofloat(ll_res_s)

  pi = 4.0d0 * atan(1.0d0)
  deg2rad = pi / 180.0d0

  fgrid  = addfile(grid_file , "r")
  finvar = addfile(invar_file, "r")

  ; ----------------------------------------------------------
  ; MPAS já vem em radianos: manter em radianos
  ; ----------------------------------------------------------
  if (isfilevar(finvar,"latCell")) then
    latCell = todouble(finvar->latCell)
    lonCell = todouble(finvar->lonCell)
  else
    latCell = todouble(fgrid->latCell)
    lonCell = todouble(fgrid->lonCell)
  end if

  if (isfilevar(finvar,"areaCell")) then
    areaCell = todouble(finvar->areaCell)
  else
    areaCell = todouble(fgrid->areaCell)
  end if

  latVertex      = todouble(fgrid->latVertex)
  lonVertex      = todouble(fgrid->lonVertex)
  verticesOnCell = tointeger(fgrid->verticesOnCell)
  nEdgesOnCell   = tointeger(fgrid->nEdgesOnCell)

  ; ajustar longitude para [-pi, pi]
  lonCell   = where(lonCell.gt.pi,  lonCell-2.0d0*pi, lonCell)
  lonCell   = where(lonCell.lt.-pi, lonCell+2.0d0*pi, lonCell)
  lonVertex = where(lonVertex.gt.pi,  lonVertex-2.0d0*pi, lonVertex)
  lonVertex = where(lonVertex.lt.-pi, lonVertex+2.0d0*pi, lonVertex)

  nCells   = dimsizes(latCell)
  maxEdges = dimsizes(verticesOnCell(0,:))

  ; ==========================================================
  ; MPAS -> SCRIP
  ; ==========================================================
  scrip_mpas = "SCRIP_MPAS_x1.163842.nc"
  system("/bin/rm -f " + scrip_mpas)

  grid_dims_mpas = new((/1/), integer)
  grid_dims_mpas(0) = nCells

  grid_center_lat = new((/nCells/), double)
  grid_center_lon = new((/nCells/), double)
  grid_imask      = new((/nCells/), integer)
  grid_area       = new((/nCells/), double)
  grid_corner_lat = new((/nCells,maxEdges/), double)
  grid_corner_lon = new((/nCells,maxEdges/), double)

  grid_center_lat = latCell
  grid_center_lon = lonCell
  grid_imask      = 1
  grid_area       = areaCell
  grid_corner_lat = 0.0d0
  grid_corner_lon = 0.0d0

  do i = 0, nCells-1
    nedges = nEdgesOnCell(i)

    if (nedges.le.0) then
      grid_imask(i) = 0
    else
      last_valid = verticesOnCell(i,nedges-1) - 1

      do j = 0, maxEdges-1
        if (j.lt.nedges) then
          vidx = verticesOnCell(i,j) - 1
        else
          vidx = last_valid
        end if

        if (vidx.ge.0) then
          grid_corner_lat(i,j) = latVertex(vidx)
          grid_corner_lon(i,j) = lonVertex(vidx)
        else
          grid_corner_lat(i,j) = 0.0d0
          grid_corner_lon(i,j) = 0.0d0
        end if
      end do
    end if
  end do

  fout = addfile(scrip_mpas,"c")
  setfileoption(fout,"DefineMode",True)

  filedimdef(fout, (/"grid_size","grid_corners","grid_rank"/), (/nCells,maxEdges,1/), (/False,False,False/))

  filevardef(fout, "grid_dims",       typeof(grid_dims_mpas), (/ "grid_rank" /))
  filevardef(fout, "grid_center_lat", typeof(grid_center_lat), (/ "grid_size" /))
  filevardef(fout, "grid_center_lon", typeof(grid_center_lon), (/ "grid_size" /))
  filevardef(fout, "grid_imask",      typeof(grid_imask), (/ "grid_size" /))
  filevardef(fout, "grid_area",       typeof(grid_area), (/ "grid_size" /))
  filevardef(fout, "grid_corner_lat", typeof(grid_corner_lat), (/ "grid_size","grid_corners" /))
  filevardef(fout, "grid_corner_lon", typeof(grid_corner_lon), (/ "grid_size","grid_corners" /))

  grid_center_lat@units = "radians"
  grid_center_lon@units = "radians"
  grid_corner_lat@units = "radians"
  grid_corner_lon@units = "radians"
  grid_area@units       = "radian2"

  filevarattdef(fout, "grid_center_lat", grid_center_lat)
  filevarattdef(fout, "grid_center_lon", grid_center_lon)
  filevarattdef(fout, "grid_corner_lat", grid_corner_lat)
  filevarattdef(fout, "grid_corner_lon", grid_corner_lon)
  filevarattdef(fout, "grid_area", grid_area)

  fout@title       = "MPAS mesh in SCRIP format"
  fout@conventions = "SCRIP"
  fout@source_grid = grid_file

  fout->grid_dims       = grid_dims_mpas
  fout->grid_center_lat = grid_center_lat
  fout->grid_center_lon = grid_center_lon
  fout->grid_imask      = grid_imask
  fout->grid_area       = grid_area
  fout->grid_corner_lat = grid_corner_lat
  fout->grid_corner_lon = grid_corner_lon

  ; ==========================================================
  ; LatLon -> SCRIP (também em radianos)
  ; ==========================================================
  scrip_ll = "SCRIP_latlon_" + ll_tag + ".nc"
  system("/bin/rm -f " + scrip_ll)

  nlat  = tointeger(180.0/ll_res)
  nlon  = tointeger(360.0/ll_res)
  gsize = nlat*nlon

  lat1d_deg = fspan(-90.0 + ll_res/2.0,  90.0 - ll_res/2.0, nlat)
  lon1d_deg = fspan(-180.0 + ll_res/2.0, 180.0 - ll_res/2.0, nlon)

  latb_deg = fspan(-90.0, 90.0, nlat+1)
  lonb_deg = fspan(-180.0, 180.0, nlon+1)

  grid_dims_ll = new((/2/), integer)
  grid_dims_ll(0) = nlon
  grid_dims_ll(1) = nlat

  ll_center_lat = new((/gsize/), double)
  ll_center_lon = new((/gsize/), double)
  ll_imask      = new((/gsize/), integer)
  ll_area       = new((/gsize/), double)
  ll_corner_lat = new((/gsize,4/), double)
  ll_corner_lon = new((/gsize,4/), double)

  k = 0
  do j = 0, nlat-1
    lat_s = todouble(latb_deg(j))   * deg2rad
    lat_n = todouble(latb_deg(j+1)) * deg2rad

    do i = 0, nlon-1
      lon_w = todouble(lonb_deg(i))   * deg2rad
      lon_e = todouble(lonb_deg(i+1)) * deg2rad

      ll_center_lat(k) = todouble(lat1d_deg(j)) * deg2rad
      ll_center_lon(k) = todouble(lon1d_deg(i)) * deg2rad
      ll_imask(k)      = 1

      ll_area(k) = (sin(lat_n) - sin(lat_s)) * (lon_e - lon_w)

      ll_corner_lat(k,0) = lat_s
      ll_corner_lon(k,0) = lon_w
      ll_corner_lat(k,1) = lat_s
      ll_corner_lon(k,1) = lon_e
      ll_corner_lat(k,2) = lat_n
      ll_corner_lon(k,2) = lon_e
      ll_corner_lat(k,3) = lat_n
      ll_corner_lon(k,3) = lon_w

      k = k + 1
    end do
  end do

  fout2 = addfile(scrip_ll,"c")
  setfileoption(fout2,"DefineMode",True)

  filedimdef(fout2, (/"grid_size","grid_corners","grid_rank"/), (/gsize,4,2/), (/False,False,False/))

  filevardef(fout2, "grid_dims",       typeof(grid_dims_ll), (/ "grid_rank" /))
  filevardef(fout2, "grid_center_lat", typeof(ll_center_lat), (/ "grid_size" /))
  filevardef(fout2, "grid_center_lon", typeof(ll_center_lon), (/ "grid_size" /))
  filevardef(fout2, "grid_imask",      typeof(ll_imask), (/ "grid_size" /))
  filevardef(fout2, "grid_area",       typeof(ll_area), (/ "grid_size" /))
  filevardef(fout2, "grid_corner_lat", typeof(ll_corner_lat), (/ "grid_size","grid_corners" /))
  filevardef(fout2, "grid_corner_lon", typeof(ll_corner_lon), (/ "grid_size","grid_corners" /))

  ll_center_lat@units = "radians"
  ll_center_lon@units = "radians"
  ll_corner_lat@units = "radians"
  ll_corner_lon@units = "radians"
  ll_area@units       = "radian2"

  filevarattdef(fout2, "grid_center_lat", ll_center_lat)
  filevarattdef(fout2, "grid_center_lon", ll_center_lon)
  filevarattdef(fout2, "grid_corner_lat", ll_corner_lat)
  filevarattdef(fout2, "grid_corner_lon", ll_corner_lon)
  filevarattdef(fout2, "grid_area", ll_area)

  fout2@title       = "Regular lat-lon grid in SCRIP format"
  fout2@conventions = "SCRIP"
  fout2@ll_res      = ll_res_s

  fout2->grid_dims       = grid_dims_ll
  fout2->grid_center_lat = ll_center_lat
  fout2->grid_center_lon = ll_center_lon
  fout2->grid_imask      = ll_imask
  fout2->grid_area       = ll_area
  fout2->grid_corner_lat = ll_corner_lat
  fout2->grid_corner_lon = ll_corner_lon

  print("SCRIP MPAS gerado : " + scrip_mpas)
  print("SCRIP LatLon gerado: " + scrip_ll)
end
EOF

export GRID_FILE
export INVAR_FILE
export LL_RES
export LL_TAG

echo "== Gerando arquivos SCRIP via NCL"
ncl gen_scrip_and_weights.ncl

echo "== Validando cabeçalhos SCRIP"
echo "----- SCRIP MPAS -----"
ncdump -h SCRIP_MPAS_x1.163842.nc
echo "----- SCRIP LatLon -----"
ncdump -h "SCRIP_latlon_${LL_TAG}.nc"

# ============================================================
# Geração dos pesos com ESMF_RegridWeightGen
# ============================================================
SRC_SCRIP="SCRIP_MPAS_x1.163842.nc"
DST_SCRIP="SCRIP_latlon_${LL_TAG}.nc"

WGT_MPAS_TO_LL="wgt_mpas_to_latlon_${LL_TAG}.nc"
WGT_LL_TO_MPAS="wgt_latlon_to_mpas_${LL_TAG}.nc"

rm -f "${WGT_MPAS_TO_LL}" "${WGT_LL_TO_MPAS}"

echo "== Gerando peso: MPAS -> LatLon"
ESMF_RegridWeightGen \
  -s "${SRC_SCRIP}" \
  -d "${DST_SCRIP}" \
  -w "${WGT_MPAS_TO_LL}" \
  -m bilinear \
  --src_type SCRIP \
  --dst_type SCRIP \
  --ignore_unmapped

echo "== Gerando peso: LatLon -> MPAS"
ESMF_RegridWeightGen \
  -s "${DST_SCRIP}" \
  -d "${SRC_SCRIP}" \
  -w "${WGT_LL_TO_MPAS}" \
  -m bilinear \
  --src_type SCRIP \
  --dst_type SCRIP \
  --ignore_unmapped

for f in "${SRC_SCRIP}" "${DST_SCRIP}" "${WGT_MPAS_TO_LL}" "${WGT_LL_TO_MPAS}"; do
    if [ ! -s "${f}" ]; then
        echo "ERRO: arquivo não existe ou está vazio: ${ESMF_DIR}/${f}"
        exit 1
    fi
done

echo "== Pesos gerados com sucesso:"
echo "   ${ESMF_DIR}/${WGT_MPAS_TO_LL}"
echo "   ${ESMF_DIR}/${WGT_LL_TO_MPAS}"
