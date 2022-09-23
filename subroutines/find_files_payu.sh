#!/bin/bash

echo -e "\n---- Finding Files ----"
echo -e "finding model output files in $base_dir for $loc_exp"
echo -e "payu-style"

indir=$base_dir/$loc_exp

echo "output_num cycle_num year_start year_end" > $here/tmp/$loc_exp/payu_info.csv

echo "searching for history"
rm -f $here/tmp/$loc_exp/payu_info.csv
rm -f $here/tmp/$loc_exp/hist_atm_files.csv
rm -f $here/tmp/$loc_exp/hist_ocn_files.csv
rm -f $here/tmp/$loc_exp/hist_ice_files.csv
payudirs=$( find ${indir} -type d -name "output[0-9][0-9][0-9]*" -printf "%p\n" | sort )
for payudir in $payudirs; do
  if [[ ! -f ${payudir}/ocean/time_stamp.out ]]; then
    continue
  fi
  echo $payudir
  yarr=()
  while IFS=' ' read -ra year; do
    yarr+=( "$( printf '%04d' $year )" )
  done < "${payudir}/ocean/time_stamp.out"
  #echo ${yarr[@]}
  payudirbase=`basename $payudir`
  payudirbaseval=$((10#${payudirbase//output/}))
  payudirbasevalf=$( printf "%04d" ${payudirbaseval##+(0)} )
  echo "$payudirbase $payudirbasevalf ${yarr[0]} ${yarr[1]}" >> $here/tmp/$loc_exp/payu_info.csv
  for atmfile in $( ls ${payudir}/atmosphere/aiihca.p* ); do
    ls $atmfile >> $here/tmp/$loc_exp/hist_atm_files.csv
  done
  for ocnfile in $( ls ${payudir}/ocean/ocean_*.nc* ); do
    ls $ocnfile >> $here/tmp/$loc_exp/hist_ocn_files.csv
  done
  if [ -d ${payudir}/ice/HISTORY/ ]; then 
    for icefile in $( ls ${payudir}/ice/HISTORY/ice*.nc ); do
      ls $icefile >> $here/tmp/$loc_exp/hist_ice_files.csv
    done
  else
    for icefile in $( ls ${payudir}/ice/ice*.nc ); do
      ls $icefile >> $here/tmp/$loc_exp/hist_ice_files.csv
    done
  fi
done

echo "searching for restarts - (restart000-style)"
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

echo -e "finished finding payu files; lists here: $here/tmp/$loc_exp"  

