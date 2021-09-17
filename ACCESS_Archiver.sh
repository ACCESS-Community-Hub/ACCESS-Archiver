#!/bin/bash
#####################
#
# This is the ACCESS Archiver, v1.0
# 15/07/2021
# 
# Developed by Chloe Mackallah, CSIRO Aspendale
#
#####
module purge
module load pbs
#####################
# GET VARS RUN FROM WRAPPER
if [ ! -z $1 ]; then
  arch_dir=$1
  base_dir=$2
  access_version=$3
  loc_exp=$4
  proj=$5
else
  echo "no experiment settings"
  exit
fi
#####################
#
# Additional NCI projects to be included in the storage flags
addprojs=( p73 )
#
# CM2 DAMIP runs only
zonal=false
if [[ $access_version == *chem ]]; then
  zonal=true
fi
#
# ESM CMIP6 runs only
plev8=false
#
# True: Use netcdf version of file if it exists
# False: Always use UM pp-file, whether or not netcdf version exists
ncexists=false
#
#####################
# FIXED SETTINGS
here=$( pwd )
mkdir -p $here/tmp/$loc_exp
rm -f $here/tmp/$loc_exp/*
for addproj in ${addprojs[@]}; do
  addstore="${addstore}+scratch/${addproj}+gdata/${addproj}"
done
####
echo -e "\n==== ACCESS_Archiver ===="
echo "base dir: $base_dir"
echo "arch dir: $arch_dir"
echo "local exp: $loc_exp"
echo "access version: $access_version"
#####################
# RUN SUBROUTINES

if [[ $access_version == om2 ]]; then
  ./subroutines/find_files_om2.sh $base_dir $loc_exp $here
elif [[ $access_version == esmpayu ]]; then
  ./subroutines/find_files_payu.sh $base_dir $loc_exp $here
else
  ./subroutines/find_files.sh $base_dir $loc_exp $here $access_version
fi
#exit

echo -e "\n---- Setting up jobs ----"

#---- um2nc parallel job ----#
cp $here/subroutines/run_um2nc.py $here/tmp/$loc_exp/run_um2nc.py
#
cat << EOF > $here/tmp/$loc_exp/job_um2nc.qsub.sh
#!/bin/bash
#PBS -P ${proj}
#PBS -l walltime=48:00:00,ncpus=24,mem=190Gb
#PBS -l wd
#PBS -l storage=scratch/${proj}+gdata/${proj}+gdata/hh5+gdata/access${addstore}
#PBS -q normal
#PBS -j oe
#PBS -N ${loc_exp}_um2nc
module purge
module use /g/data/hh5/public/modules
module use ~access/modules
module load cdo
module load nco
module load pythonlib/um2netcdf4/2.0
export ncpus=\$PBS_NCPUS
export here=$here
export base_dir=$base_dir
export arch_dir=$arch_dir
export loc_exp=$loc_exp
export zonal=$zonal
export access_version=$access_version
export plev8=$plev8
export ncexists=$ncexists
export UMDIR=/projects/access/umdir

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
#PBS -P ${proj}
#PBS -l walltime=48:00:00,ncpus=1,mem=12Gb
#PBS -l wd
#PBS -l storage=scratch/${proj}+gdata/${proj}+gdata/hh5+gdata/access${addstore}
#PBS -q normal
#PBS -j oe
#PBS -N ${loc_exp}_mppnc
module purge
module use /g/data/hh5/public/modules
module use ~access/modules
module load cdo
module load nco
module load conda/analysis3
export here=$here
export base_dir=$base_dir
export arch_dir=$arch_dir
export loc_exp=$loc_exp
export access_version=$access_version

echo -e "\n==== ACCESS_Archiver -- mppnccombine ===="
echo "base dir: $base_dir"
echo "arch dir: $arch_dir"
echo "local exp: $loc_exp"
echo "access version: $access_version"

$here/tmp/$loc_exp/mppnccomb_check.sh

EOF
if [[ $access_version != om2 ]] || [[ $access_version != *amip ]] || [[ $access_version != *chem ]]; then
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
elif [[ $access_version == *amip ]] || [[ $access_version == *chem ]]; then
  cp $here/subroutines/cp_rest.sh $here/tmp/$loc_exp/cp_rest.sh
else
  cp $here/subroutines/cp_hist.sh $here/tmp/$loc_exp/cp_hist.sh
  cp $here/subroutines/cp_rest.sh $here/tmp/$loc_exp/cp_rest.sh
fi

#
cat << EOF > $here/tmp/$loc_exp/job_arch.qsub.sh
#!/bin/bash
#PBS -P ${proj}
#PBS -l walltime=48:00:00,ncpus=1,mem=8Gb
#PBS -l wd
#PBS -l storage=scratch/${proj}+gdata/${proj}+gdata/hh5+gdata/access${addstore}
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
export here=$here
export base_dir=$base_dir
export arch_dir=$arch_dir
export loc_exp=$loc_exp
export access_version=$access_version

echo -e "\n==== ACCESS_Archiver -- copy_job ===="
echo "base dir: $base_dir"
echo "arch dir: $arch_dir"
echo "local exp: $loc_exp"
echo "access version: $access_version"


if [[ $access_version == om2 ]]; then
  $here/tmp/$loc_exp/link_arch_om2.sh
elif [[ $access_version == *amip ]] || [[ $access_version == *chem ]]; then
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
