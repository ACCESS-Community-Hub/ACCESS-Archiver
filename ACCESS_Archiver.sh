#!/bin/bash
source  /etc/profile.d/modules.sh
module purge
module load pbs
set -a
#########################
#
# This is the ACCESS Archiver, v1.1
# 21/01/2022
#
# Developed by Chloe Mackallah, CSIRO Aspendale
#
#########################
# NON-STANDARD USER OPTIONS

#split zonal/non-zonal files - CM2 DAMIP and CM2-Chem runs only
zonal=false

#reduce daily plev19 data to plev8 - ESM CMIP6 runs only
plev8=false

#convert_unknown = [true, false]; convert unrecognised pp files that are found?
convert_unknown=false

#########################
# DO NOT EDIT - FIXED TASKS

#check wrapper is used
if [ -z $arch_dir ]; then
  echo "no experiment settings"; exit
fi
if [ -z $here ]; then
  here=$( pwd )
fi
mkdir -p $here/tmp/$loc_exp
rm -f $here/tmp/$loc_exp/*
#identify NCI project of base_dir
IFS='/'
read -a base_dir_split <<< $base_dir
for bdse in ${base_dir_split[@]}; do
  if [[ $bdse == '' ]] || [[ $bdse == ' ' ]] || [[ $bdse == 'g' ]] || \
    [[ $bdse == 'data' ]] || [[ $bdse == 'scratch' ]]; then
    continue
  fi
  base_grp=$bdse
  break
done
#identify NCI project of arch_dir
read -a arch_dir_split <<< $arch_dir
for adse in ${arch_dir_split[@]}; do
  if [[ $adse == '' ]] || [[ $adse == ' ' ]] || [[ $adse == 'g' ]] || \
    [[ $adse == 'data' ]] || [[ $adse == 'scratch' ]]; then
    continue
  fi
  arch_grp=$adse
  break
done
IFS=' '
mkdir -p $arch_dir/$loc_exp/{history/atm/netCDF,restart/atm}
chgrp -R $arch_grp $arch_dir/$loc_exp
if [[ $access_version == *chem ]]; then
  zonal=true
fi
#
#########################
# PRINT DETAILS TO SCREEN

echo -e "\n==== ACCESS_Archiver ===="
echo "here: $here"
echo "compute project: $comp_proj"
echo "base directory: $base_dir"
echo "archive directory: $arch_dir"
echo "local experiment: $loc_exp"
echo "access version: $access_version"
echo "subdaily atm data: $subdaily"

#########################
# RUN SUBROUTINES

if [[ $access_version == om2 ]]; then
  ${here}/subroutines/find_files_om2.sh
elif [[ $access_version == esmpayu ]]; then
  ${here}/subroutines/find_files_payu.sh
else
  ${here}/subroutines/find_files.sh
fi

if [[ -n $first_year || -n $last_year ]]; then
  first_year=${first_year:-1}
  last_year=${last_year:-9999}
  echo "Archiving restricted to years" $first_year ":" $last_year
  for file in $here/tmp/$loc_exp/*csv; do
    python3 $here/subroutines/restrict_years.py $first_year $last_year $file
    if [[ $? != 0 ]]; then
      echo "Error subsetting csv file"
      exit 1
    fi
  done
fi

echo -e "\n---- Setting up jobs ----"

#---- um2nc parallel job ----#
cp $here/subroutines/run_um2nc.py $here/tmp/$loc_exp/run_um2nc.py
#
cat << EOF > $here/tmp/$loc_exp/job_um2nc.qsub.sh
#!/bin/bash
#PBS -P ${comp_proj}
#PBS -l walltime=48:00:00,ncpus=24,mem=190Gb
#PBS -l wd
#PBS -l storage=scratch/${base_grp}+gdata/${base_grp}+scratch/${arch_grp}+gdata/${arch_grp}+gdata/hh5+gdata/access
#PBS -q normal
#PBS -j oe
#PBS -N ${loc_exp}_um2nc
module purge
module use /g/data/hh5/public/modules
module use ~access/modules
module load cdo
module load nco
module load pythonlib/um2netcdf4/2.0
set -a
ncpus=\$PBS_NCPUS
here=$here
base_dir=$base_dir
arch_dir=$arch_dir
arch_grp=$arch_grp
loc_exp=$loc_exp
zonal=$zonal
access_version=$access_version
plev8=$plev8
ncexists=$ncexists
subdaily=$subdaily
convert_unknown=$convert_unknown
UMDIR=/projects/access/umdir

echo -e "\n==== ACCESS_Archiver -- um2netcdf_iris ===="
echo "base dir: $base_dir"
echo "arch dir: $arch_dir"
echo "local exp: $loc_exp"
echo "access version: $access_version"

python -W ignore $here/tmp/$loc_exp/run_um2nc.py

EOF
if [[ $access_version != om2 ]]; then
  ls $here/tmp/$loc_exp/job_um2nc.qsub.sh
  chmod +x $here/tmp/$loc_exp/job_um2nc.qsub.sh
  qsub $here/tmp/$loc_exp/job_um2nc.qsub.sh
fi
#----------------------------#

#exit

#---- mppnccombine job --------------#
cp $here/subroutines/mppnccomb_check.sh $here/tmp/$loc_exp/mppnccomb_check.sh
#
cat << EOF > $here/tmp/$loc_exp/job_mppnc.qsub.sh
#!/bin/bash
#PBS -P ${comp_proj}
#PBS -l walltime=48:00:00,ncpus=1,mem=12Gb
#PBS -l wd
#PBS -l storage=scratch/${base_grp}+gdata/${base_grp}+scratch/${arch_grp}+gdata/${arch_grp}+gdata/hh5+gdata/access
#PBS -q normal
#PBS -j oe
#PBS -N ${loc_exp}_mppnc
module purge
module use /g/data/hh5/public/modules
module use ~access/modules
module load cdo
module load nco
module load conda/analysis3
set -a
here=$here
base_dir=$base_dir
arch_dir=$arch_dir
arch_grp=$arch_grp
loc_exp=$loc_exp
access_version=$access_version

echo -e "\n==== ACCESS_Archiver -- mppnccombine ===="
echo "base dir: $base_dir"
echo "arch dir: $arch_dir"
echo "local exp: $loc_exp"
echo "access version: $access_version"

$here/tmp/$loc_exp/mppnccomb_check.sh

EOF
if [[ $access_version != om2 ]] || [[ $access_version != *amip ]]; then #|| [[ $access_version != *chem ]]; then
  ls $here/tmp/$loc_exp/job_mppnc.qsub.sh
  chmod +x $here/tmp/$loc_exp/job_mppnc.qsub.sh
  #qsub $here/tmp/$loc_exp/job_mppnc.qsub.sh
fi
#----------------------------#
#exit
#---- copy job --------------#
if [[ $access_version == *payu* ]]; then
  cp $here/subroutines/cp_hist_payu.sh $here/tmp/$loc_exp/cp_hist.sh
  cp $here/subroutines/cp_rest_payu.sh $here/tmp/$loc_exp/cp_rest.sh
elif [[ $access_version == om2 ]]; then
  cp $here/subroutines/link_arch_om2.sh $here/tmp/$loc_exp/link_arch_om2.sh
elif [[ $access_version == *amip ]]; then #|| [[ $access_version == *chem ]]; then
  cp $here/subroutines/cp_rest.sh $here/tmp/$loc_exp/cp_rest.sh
else
  cp $here/subroutines/cp_hist.sh $here/tmp/$loc_exp/cp_hist.sh
  cp $here/subroutines/cp_rest.sh $here/tmp/$loc_exp/cp_rest.sh
fi

#
cat << EOF > $here/tmp/$loc_exp/job_arch.qsub.sh
#!/bin/bash
#PBS -P ${comp_proj}
#PBS -l walltime=48:00:00,ncpus=1,mem=8Gb
#PBS -l wd
#PBS -l storage=scratch/${base_grp}+gdata/${base_grp}+scratch/${arch_grp}+gdata/${arch_grp}+gdata/hh5+gdata/access
#PBS -q normal
#PBS -j oe
#PBS -N ${loc_exp}_arch
##PBS -W depend=beforeany:$mppn
module purge
module use /g/data/hh5/public/modules
module use ~access/modules
module load cdo
module load nco
module load conda/analysis3
set -a
here=$here
base_dir=$base_dir
arch_dir=$arch_dir
arch_grp=$arch_grp
loc_exp=$loc_exp
access_version=$access_version

echo -e "\n==== ACCESS_Archiver -- copy_job ===="
echo "base dir: $base_dir"
echo "arch dir: $arch_dir"
echo "local exp: $loc_exp"
echo "access version: $access_version"


if [[ $access_version == om2 ]]; then
  $here/tmp/$loc_exp/link_arch_om2.sh
elif [[ $access_version == *amip ]]; then #|| [[ $access_version == *chem ]]; then
  $here/tmp/$loc_exp/cp_rest.sh
else
  $here/tmp/$loc_exp/cp_hist.sh
  $here/tmp/$loc_exp/cp_rest.sh
  qsub $here/tmp/$loc_exp/job_mppnc.qsub.sh
fi

EOF
ls $here/tmp/$loc_exp/job_arch.qsub.sh
chmod +x $here/tmp/$loc_exp/job_arch.qsub.sh
qsub $here/tmp/$loc_exp/job_arch.qsub.sh
#----------------------------#

echo -e "\n---- DONE: $loc_exp ----"
