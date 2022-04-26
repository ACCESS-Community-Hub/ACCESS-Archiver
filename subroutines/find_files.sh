#!/bin/bash

if [ -z $base_dir ]; then
  echo "information not provided to subroutines/find_files.sh"
  exit
fi

echo -e "\n---- Finding Files ----"
echo -e "finding model output files in $base_dir for $loc_exp"

if [[ -d $base_dir/$loc_exp/history ]]; then #&& [[ $access_version != *amip ]]; then
  echo "assuming standard dir structure"
  dir_struc=0
elif [[ -d $base_dir/u-$loc_exp/share/data/History_Data ]]; then # && [[ $access_version == *amip ]]; then
  echo "assuming cylc-run dir structure; atm-only"
  dir_struc=1
else
  echo "could not identify dir structure, check if amip; exiting"
  exit
fi

echo "searching for history"
if [ $dir_struc == 0 ]; then
  find $base_dir/$loc_exp/history/atm -name "*.p*" -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/hist_atm_files.csv
  find $base_dir/$loc_exp/history/ocn -name "ocean*.nc*" -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/hist_ocn_files.csv
  find $base_dir/$loc_exp/history/ice -name "ice*.nc*" -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/hist_ice_files.csv
elif [ $dir_struc == 1 ]; then
  find $base_dir/u-$loc_exp/share/data/History_Data -name "*.p*" -type f -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/hist_atm_files.csv
fi

echo "searching for restarts"
if [ $dir_struc == 0 ]; then
  find $base_dir/$loc_exp/restart/atm/* -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/rest_atm_files.csv
  find $base_dir/$loc_exp/restart/ocn/* -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/rest_ocn_files.csv
  find $base_dir/$loc_exp/restart/ice/* -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/rest_ice_files.csv
  find $base_dir/$loc_exp/restart/cpl/* -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/rest_cpl_files.csv
elif [ $dir_struc == 1 ]; then
  find $base_dir/u-$loc_exp/share/data/History_Data/ -name "*.da*" -type f -printf "%p\n" | sort \
      > $here/tmp/$loc_exp/rest_atm_files.csv
fi

echo -e "finished finding files; lists here: $here/tmp/$loc_exp"
