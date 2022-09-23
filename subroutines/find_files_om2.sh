#!/bin/bash

echo -e "\n---- Finding Files ----"
echo -e "finding model output files in $base_dir for $loc_exp"
echo -e "OM2-style"

indir=$base_dir/$loc_exp

echo "output_num cycle_num year_start year_end" > $here/tmp/$loc_exp/om2_info.csv

echo "searching for history"
rm -f $here/tmp/$loc_exp/om2_info.csv
rm -f $here/tmp/$loc_exp/hist_ocn_files.csv
rm -f $here/tmp/$loc_exp/hist_ice_files.csv
om2dirs=$( find ${indir} -type d -name "output[0-9][0-9][0-9]*" -printf "%p\n" | sort )
for om2dir in $om2dirs; do
  #echo $om2dir
  yarr=()
  while IFS=' ' read -ra year; do
    yarr+=( "$( printf '%04d' $year )" )
  done < "${om2dir}/ocean/time_stamp.out"
  #echo ${yarr[@]}
  om2dirbase=`basename $om2dir`
  om2dirbaseval=$((10#${om2dirbase//output/} + 1))
  om2dirbasevalf=$( printf "%04d" ${om2dirbaseval##+(0)} )
  echo "$om2dirbase $om2dirbasevalf ${yarr[0]} ${yarr[1]}" >> $here/tmp/$loc_exp/om2_info.csv
  for ocnfile in $( ls ${om2dir}/ocean/ocean_*.nc* ); do
    ls $ocnfile >> $here/tmp/$loc_exp/hist_ocn_files.csv
  done
  for icefile in $( ls ${om2dir}/ice/OUTPUT/ice*.nc ); do
    ls $icefile >> $here/tmp/$loc_exp/hist_ice_files.csv
  done
done

exit

#RESTARTS NO LONGER SAVED FOR OM2
echo "searching for restarts"
rm -f $here/tmp/$loc_exp/rest_dirs.csv
restdirs=$( find ${indir} -type d -name "restart[0-9][0-9][0-9]*" -printf "%p\n" | sort )
for restdir in $restdirs; do
  restdirbase=`basename $restdir`
  restdirbaseval=$((10#${restdirbase//restart/}))
  if ! (( ${restdirbaseval} % 5 )) ; then
    echo $restdir
    echo $restdir >> $here/tmp/$loc_exp/rest_dirs.csv
  fi
done

echo -e "finished finding OM2 files; lists here: $here/tmp/$loc_exp"  

