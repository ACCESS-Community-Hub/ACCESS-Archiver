import os, sys, collections, csv
import multiprocessing as mp
import um2netcdf4
import subprocess as sp
import mule
import shutil
import string
import netCDF4 as nc4
import re

try: ncpus=int(os.environ.get('ncpus'))
except: ncpus=1
here=os.environ.get('here')
base_dir=os.environ.get('base_dir')
arch_dir=os.environ.get('arch_dir')
arch_grp=os.stat(arch_dir).st_gid
loc_exp=os.environ.get('loc_exp')
access_version=os.environ.get('access_version')
if os.environ.get('subdaily').lower() in ['true','yes','1']: subdaily=True
else: subdaily=False
if os.environ.get('ncexists').lower() in ['true','yes','1']: ncexists=True
else: ncexists=False
if os.environ.get('zonal').lower() in ['true','yes','1']: zonal=True
else: zonal=False
if os.environ.get('plev8').lower() in ['true','yes','1']: plev8=True
else: plev8=False
if os.environ.get('convert_unknown').lower() in ['true','yes','1']: convert_unknown=True
else: convert_unknown=False
Args = collections.namedtuple('Args',\
    'nckind compression simple nomask hcrit verbose include_list exclude_list nohist use64bit')
args = Args(3, 4, True, False, 0.5, False, None, None, False, False)
monmap={"jan":"01","feb":"02","mar":"03","apr":"04","may":"05","jun":"06",\
    "jul":"07","aug":"08","sep":"09","oct":"10","nov":"11","dec":"12"}

def get_payu_year(file,payu_info):
    with open(payu_info) as payu_csv:
        payu_reader = csv.reader(payu_csv, delimiter=' ')
        for row in payu_reader:
            if file.find(row[0]) != -1:
                payu_yr=row[2]
    try:
        payu_yr
        return payu_yr
    except: sys.exit('cannot determine payu year!')

def do_plev8(outname):
    if (outname.find('.pe') != -1) or (outname.find('.pd') != -1):
        nc=nc4.Dataset(outname)
        try:
            ncplev=nc.variables['pressure']
            if ncplev.shape[0] == 19:
                print('attempting plev8 conversion')
                [dirname,basename]=os.path.split(outname)
                os.makedirs(dirname+'/plev19_daily',exist_ok=True)
                chutil.chown(dirname+'/plev19_daily',group=arch_grp)
                plev19file=dirname+'/plev19_daily/'+basename
                plev8file=outname+'_plev8'
                os.rename(outname,plev19file)
                if int(ncplev[0]) in [1,100]:
                    output = sp.run(['ncks','-d','pressure,2','-d','pressure,5','-d','pressure,7','-d',\
                        'pressure,10','-d','pressure,13','-d','pressure,15','-d','pressure,16','-d',\
                        'pressure,18',plev19file,plev8file],capture_output=True,text=True)
                elif int(ncplev[0]) in [100000,1000]:
                    output = sp.run(['ncks','-d','pressure,0','-d','pressure,2','-d','pressure,3','-d',\
                        'pressure,5','-d','pressure,8','-d','pressure,11','-d','pressure,13','-d',\
                        'pressure,16',plev19file,plev8file],capture_output=True,text=True)
                else:
                    print('pressure information not recognised, moving original file back')
                    os.rename(plev19file,outname)
                    return
                if output.returncode != 0:
                    print('issue; moving original file back')
                    os.rename(plev19file,outname)
                    return
                else:
                    os.replace(plev8file,outname)
                    print('converted to plev8')
                    return
            else:
                print('plev19 not found')
                return
        except:
            print('pressure variables not found')
            return
    else: return

def fix_esm_lbvc9(file,outname):
    lbvc9=False
    ff=mule.FieldsFile.from_file(file, 'r')
    for fld in ff.fields:
        if fld.lbvc == 9:
            fld.lbvc=65
            lbvc9=True
    if lbvc9:
        ff.to_file(outname.replace('.nc','')+'_lbvc9-fixed')
    return lbvc9

def check_um2nc(file,freq):
    print(file)
    basename=os.path.basename(file)
    if arch_dir == base_dir:
        print(basename+': already archived')
        if plev8: do_plev8(file)
        sys.stdout.flush()
    elif basename.find('.nc') != -1:
        if ncexists:
            print(basename, 'already netcdf, copying')
            for key in monmap.keys():
                if basename.find(key) != -1:
                    basename=basename.replace(key,monmap[key]).replace('.nc','')
            outname=arch_dir+'/'+loc_exp+'/history/atm/netCDF/'+basename+'_'+freq+'.nc'
            if not os.path.exists(outname):
                shutil.copyfile(file,outname+'_tmp')
                os.replace(outname+'_tmp',outname)
                if plev8: do_plev8(outname)
                os.chmod(outname,0o644)
                shutil.chown(outname,group=arch_grp)
            else:
                print(basename+': file already exists')
            sys.stdout.flush()
        elif (not ncexists) and (not os.path.exists(file.replace('.nc',''))):
            print(basename, 'UM pp files does not exist, using nc file')
            for key in monmap.keys():
                if basename.find(key) != -1:
                    basename=basename.replace(key,monmap[key]).replace('.nc','')
            outname=arch_dir+'/'+loc_exp+'/history/atm/netCDF/'+basename+'_'+freq+'.nc'
            if not os.path.exists(outname):
                shutil.copyfile(file,outname+'_tmp')
                os.replace(outname+'_tmp',outname)
                if plev8: do_plev8(outname)
                os.chmod(outname,0o644)
                shutil.chown(outname,group=arch_grp)
            else:
                print(basename+': file already exists')
            sys.stdout.flush()
    else:
        if os.path.exists(file+'.nc') and ncexists:
            print(basename, 'nc file exists, skipping')
            sys.stdout.flush()
        else:
            print(basename, 'needs converting, um2ncing')
            if zonal:
                #do_um2nc_zonal(file,freq)
                if access_version.find('chem') != -1:
                    if freq == 'dai': do_um2nc_zonal(file,freq)
                    else: do_um2nc(file,freq)
                else:
                    if freq == 'dai': do_um2nc_zonal(file,freq)
                    else: do_um2nc(file,freq)
            else: do_um2nc(file,freq)

def do_um2nc(file,freq):
    basename=os.path.basename(file)
    if access_version.find('payu') != -1:
        try: del payu_yr
        except: pass
        payu_yr=get_payu_year(file,here+'/tmp/'+loc_exp+'/payu_info.csv')
        mth=monmap[basename.split('.')[-1][-3:]]
        outname=arch_dir+'/'+loc_exp+'/history/atm/netCDF/{}.p{}-{}{}_'\
            .format(loc_exp,basename.split('.')[-1][1],payu_yr,mth)+freq+'.nc'
        #print(outname)
    else:
        for key in monmap.keys():
            if basename.find(key) != -1: basename=basename.replace(key,monmap[key])
        if re.compile('-[0-9][0-9][0-9][0-9]0[0-9][0-9]001').search(basename) is not None:
            testname=basename.split('-')
            testyear=testname[-1][:4]
            testmonth=testname[-1][5:7]
            psplit=basename.split('.p')
            basename=psplit[0]+'.p'+psplit[1][0]+'-'+testyear+testmonth
        outname=arch_dir+'/'+loc_exp+'/history/atm/netCDF/'+basename+'_'+freq+'.nc'
        #print(outname)
    try: os.remove(outname+'_tmp')
    except: pass
    try: os.remove(outname.replace('.nc','')+'_lbvc9-fixed')
    except: pass
    if not os.path.exists(outname):
        print(outname)
        if access_version.find('esm') != -1:
            lbvc9=fix_esm_lbvc9(file,outname)
            if lbvc9:
                try: um2netcdf4.process(outname.replace('.nc','')+'_lbvc9-fixed',outname+'_tmp',args)
                except Exception as e:
                    print('um2nc conversion failed: {}'.format(e))
                    os.remove(outname+'_tmp')
                    return
                os.remove(outname.replace('.nc','')+'_lbvc9-fixed')
            else:
                try: um2netcdf4.process(file,outname+'_tmp',args)
                except Exception as e:
                    print('um2nc conversion failed: {}'.format(e))
                    os.remove(outname+'_tmp')
                    return
        else:
            try: um2netcdf4.process(file,outname+'_tmp',args)
            except Exception as e:
                print('um2nc conversion failed: {}'.format(e))
                os.remove(outname+'_tmp')
                return
        os.replace(outname+'_tmp',outname)
        if plev8: do_plev8(outname)
        os.chmod(outname,0o644)
        shutil.chown(outname,group=arch_grp)
        try:
            if os.path.getsize(outname) < 1024:
                print('removing empty file: ',outname)
                os.remove(outname)
        except: pass
        sys.stdout.flush()
    else:
        print(basename+': file already exists')
        if plev8: do_plev8(outname)
        sys.stdout.flush()

def do_um2nc_zonal(file,freq):
    basename=os.path.basename(file)
    os.makedirs(arch_dir+'/'+loc_exp+'/history/atm/zonal/',exist_ok=True)
    shutil.chown(arch_dir+'/'+loc_exp+'/history/atm/zonal/',group=arch_grp)
    tmpname=arch_dir+'/'+loc_exp+'/history/atm/zonal/'+basename
    for key in monmap.keys():
        if basename.find(key) != -1:
            basename=basename.replace(key,monmap[key])
    outname=arch_dir+'/'+loc_exp+'/history/atm/netCDF/'+basename+'_'+freq+'.nc'
    try: os.remove(outname+'_tmp')
    except: pass
    try: os.remove(outname+"_zonal_tmp")
    except: pass
    try: os.remove(tmpname+"_zonal")
    except: pass
    try: os.remove(tmpname+"_nonzonal")
    except: pass
    if not os.path.exists(outname):
        print(basename)
        sp.run(["mule-select",file,tmpname+"_zonal","--include","lbnpt=1"],capture_output=False)
        sp.run(["mule-select",file,tmpname+"_nonzonal","--exclude","lbnpt=1"],capture_output=False)
        try:
            try: um2netcdf4.process(tmpname+"_zonal",outname+"_zonal_tmp",args)
            except Exception as e:
                print('um2nc conversion failed: {}'.format(e))
                os.remove(outname+'_zonal_tmp')
                return
            os.replace(outname+"_zonal_tmp",outname+"_zonal")
            os.chmod(outname+"_zonal",0o644)
            shutil.chown(outname+"_zonal",group=arch_grp)
        except: print('no zonal data')
        try:
            try: um2netcdf4.process(tmpname+"_nonzonal",outname+'_tmp',args)
            except Exception as e:
                print('um2nc conversion failed: {}'.format(e))
                os.remove(outname+'_tmp')
                return
            os.replace(outname+'_tmp',outname)
            os.chmod(outname,0o644)
            shutil.chown(outname,group=arch_grp)
        except: print('no nonzonal data')
        os.remove(tmpname+"_nonzonal")
        os.remove(tmpname+"_zonal")
        try:
            if os.path.getsize(outname) < 1024:
                print('removing empty file: ',outname)
                os.remove(outname)
        except: pass
        try:
            if os.path.getsize(outname+"_zonal") < 1024:
                print('removing empty file: ',outname+"_zonal")
                os.remove(outname+"_zonal")
        except: pass
        sys.stdout.flush()
    else:
        print(basename+': file already exists')
        sys.stdout.flush()

def read_files(here,loc_exp):
    print('reading '+here+'/tmp/'+loc_exp+'/hist_atm_files.csv')
    hist_atm_mon=[]
    hist_atm_dai=[]
    hist_atm_6hr=[]
    hist_atm_3hr=[]
    hist_atm_dai10=[]
    hist_atm_oth=[]
    try:
        with open(here+'/tmp/'+loc_exp+'/hist_atm_files.csv',newline='') as csvfile:
            read=csv.reader(csvfile)
            for row in read:
                if access_version.find('chem') != -1:
                    if any(mon in os.path.basename(row[0]) for mon in ['.pm','.pa']):
                        hist_atm_mon.append(row[0])
                    elif any(dai in os.path.basename(row[0]) for dai in ['.pd','.pc']):
                        hist_atm_dai.append(row[0])
                    elif any(dai10 in os.path.basename(row[0]) for dai10 in ['.pe']):
                        hist_atm_dai10.append(row[0])
                    else: hist_atm_oth.append(row[0])
                else:
                    if any(mon in os.path.basename(row[0]) for mon in ['.pm','.pa']):
                        hist_atm_mon.append(row[0])
                    elif any(dai in os.path.basename(row[0]) for dai in ['.pd','.pe']):
                        hist_atm_dai.append(row[0])
                    elif any(sixhr in os.path.basename(row[0]) for sixhr in ['.p7','.pj']):
                        hist_atm_6hr.append(row[0])
                    elif any(threehr in os.path.basename(row[0]) for threehr in ['.p8','.pi']):
                        hist_atm_3hr.append(row[0])
                    else: hist_atm_oth.append(row[0])
    except: print('file not found: '+here+'/tmp/'+loc_exp+'/hist_atm_files.csv')
    hist_atm=[hist_atm_mon,hist_atm_dai,hist_atm_6hr,hist_atm_3hr,hist_atm_dai10,hist_atm_oth]
    return hist_atm

def main():
    print('\n---- Run um2netCDF4 ----')
    # Read in file list from tmp/$loc_exp
    hist_atm=read_files(here,loc_exp)
    hist_atm_mon,hist_atm_dai,hist_atm_6hr,hist_atm_3hr,hist_atm_dai10,hist_atm_oth=hist_atm
    if len(hist_atm_mon)+len(hist_atm_dai)+len(hist_atm_6hr)+len(hist_atm_3hr)+len(hist_atm_dai10)+len(hist_atm_oth) > 0:
        os.makedirs(arch_dir+'/'+loc_exp+'/history/atm/netCDF',exist_ok=True)
        shutil.chown(arch_dir+'/'+loc_exp+'/history/atm/netCDF',group=arch_grp)
    else:
        print('no atm history files found')
    # Do um2netcdf
    print('converting UM files to netCDF4')
    print('multiprocessor sees {} cpus'.format(ncpus))
    print('zonal processing is {}'.format(zonal))
    print('subdaily processing is {}'.format(subdaily))
    if len(hist_atm_mon) > 0:
        print('\nfound '+str(len(hist_atm_mon))+' monthly atm files')
        if ncpus == 1:
            for file in hist_atm_mon:
                check_um2nc(file,'mon')
        else:
            with mp.Pool(ncpus) as pool:
                pool.starmap(check_um2nc,((file,'mon') for file in hist_atm_mon))
    if len(hist_atm_dai) > 0:
        print('\nfound '+str(len(hist_atm_dai))+' daily atm files')
        if ncpus == 1:
            for file in hist_atm_dai:
                check_um2nc(file,'dai')
        else:
            with mp.Pool(ncpus) as pool:
                pool.starmap(check_um2nc,((file,'dai') for file in hist_atm_dai))
    if len(hist_atm_6hr) > 0 and subdaily:
        print('\nfound '+str(len(hist_atm_6hr))+' 6-hourly atm files')
        if ncpus == 1:
            for file in hist_atm_6hr:
                check_um2nc(file,'6h')
        else:
            with mp.Pool(ncpus) as pool:
                pool.starmap(check_um2nc,((file,'6h') for file in hist_atm_6hr))
    if len(hist_atm_3hr) > 0 and subdaily:
        print('\nfound '+str(len(hist_atm_3hr))+' 3-hourly atm files')
        if ncpus == 1:
            for file in hist_atm_3hr:
                check_um2nc(file,'3h')
        else:
            with mp.Pool(ncpus) as pool:
                pool.starmap(check_um2nc,((file,'3h') for file in hist_atm_3hr))
    if len(hist_atm_dai10) > 0:
        print('\nfound '+str(len(hist_atm_dai10))+' 10-daily atm files')
        if ncpus == 1:
            for file in hist_atm_dai10:
                check_um2nc(file,'dai10')
        else:
            with mp.Pool(ncpus) as pool:
                pool.starmap(check_um2nc,((file,'chem') for file in hist_atm_dai10))
    if len(hist_atm_oth) > 0:
        if convert_unknown:
            print('\nfound '+str(len(hist_atm_oth))+' unknown atm files')
            if ncpus == 1:
                for file in hist_atm_oth:
                    check_um2nc(file,'unknown')
                    #break
            else:
                with mp.Pool(ncpus) as pool:
                    pool.starmap(check_um2nc,((file,'unknown') for file in hist_atm_oth))
        else:
            print('\nfound '+str(len(hist_atm_oth))+' unidentified atm files (will not be converted):')
        #for file in hist_atm_oth:
        #    print(file)
    print('um2netCDF_iris complete')

if __name__ == "__main__":
    main()
