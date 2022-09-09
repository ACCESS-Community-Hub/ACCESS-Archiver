# Select only lines within the given year range.
# MOM output may include grid files without a year number. These are
# always included.

import sys, tempfile, re, os, shutil

first_year = int(sys.argv[1])
last_year = int(sys.argv[2])
csvfile = sys.argv[3]

# Assume first 4 digits in filename are the year
year_re = re.compile('\d{4}')

# UM restart files and the CICE restart iced file use year number from
# start of the next run, so keep an extra year for these
if os.path.basename(csvfile) in ('rest_atm_files.csv', 'rest_ice_files.csv'):
    extra = 1
else:
    extra = 0

tmpfile = tempfile.mktemp()

with open(csvfile) as f_in, open(tmpfile,'w') as f_out:
    for l in f_in.readlines():
        m = year_re.search(os.path.basename(l.strip()))
        year = None
        try:
            year = int(m.group())
        except:
            print(f"No year number in {l.strip()}")
        if year is None or first_year <= year <= last_year+extra:
            f_out.write(l)

shutil.move(tmpfile,csvfile)
